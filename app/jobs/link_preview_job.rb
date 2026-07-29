# frozen_string_literal: true

require "net/http"
require "resolv"
require "ipaddr"

# Разворачивает первую ссылку сообщения в карточку (og:title / og:description / og:image).
# Ходит в сеть, поэтому вынесено в джобу: канал не должен ждать чужой сервер.
# Готовую карточку рассылаем тем же broadcast'ом — клиент апсертит сообщение по id.
class LinkPreviewJob < ApplicationJob
  queue_as :default

  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5
  MAX_REDIRECTS = 2
  # Открывающих тегов хватает: og-теги живут в <head>, тянуть страницу целиком незачем.
  MAX_BYTES = 200_000
  FORBIDDEN_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
    169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
  ].map { |network| IPAddr.new(network) }.freeze

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil? || message.deleted?

    url = message.first_link
    return if url.blank?

    preview = build_preview(url)
    return if preview.blank?

    message.update_column(:link_preview, preview.to_json)
    message.room.broadcast_message(message.reload)
  end

  private

  def build_preview(url)
    html = fetch_html(url)
    return if html.blank?

    title = meta(html, "og:title") || html[%r{<title[^>]*>(.*?)</title>}mi, 1]
    preview = {
      "url" => url,
      "title" => clean(title),
      "description" => clean(meta(html, "og:description") || meta_name(html, "description")),
      "image_url" => absolute_url(url, meta(html, "og:image")),
      "site_name" => clean(meta(html, "og:site_name")) || URI.parse(url).host
    }.compact

    # Без заголовка карточка вырождается в голую ссылку — такую не рисуем.
    preview if preview["title"].present?
  end

  def fetch_html(url, redirects_left = MAX_REDIRECTS)
    uri = URI.parse(url)
    return unless safe_uri?(uri)

    response = request(uri)

    if response.is_a?(Net::HTTPRedirection) && redirects_left.positive?
      return fetch_html(URI.join(url, response["location"]).to_s, redirects_left - 1)
    end

    return unless response.is_a?(Net::HTTPSuccess)
    return unless response["content-type"].to_s.include?("text/html")

    response.body
  rescue StandardError => error
    Rails.logger.info("LinkPreviewJob: #{url} не открылся — #{error.class}: #{error.message}")
    nil
  end

  def request(uri)
    # Net::HTTP, открывая сокет, резолвил бы `uri.host` заново — и между нашей проверкой адресов
    # и этим вторым резолвом DNS успевает ответить уже приватным адресом (DNS rebinding).
    # Поэтому подключаемся к уже проверенному IP, оставляя исходное имя хоста для TLS и SNI.
    address = public_addresses(uri.host).first
    raise "no public address" if address.nil?

    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    http.start do |session|
      get = Net::HTTP::Get.new(uri, "User-Agent" => "SodrujestvoChatBot/1.0", "Accept" => "text/html")

      session.request(get) do |response|
        return response unless response.is_a?(Net::HTTPSuccess)

        body = +""
        response.read_body do |chunk|
          remaining = MAX_BYTES - body.bytesize
          body << chunk.byteslice(0, remaining)
          break if body.bytesize >= MAX_BYTES
        end
        # Тело приходит бинарной строкой: без явной перекодировки заголовки уедут в JSON как BINARY.
        # read_body уже прочитан — подкладываем усечённое тело, чтобы вызвавший его увидел.
        response.instance_variable_set(:@body, body.force_encoding(Encoding::UTF_8).scrub)
        response.instance_variable_set(:@read, true)
        return response
      end
    end
  end

  # Защита от SSRF: разрешаем только HTTPS, стандартный порт и хост, у которого ВСЕ
  # DNS-адреса публичны. Проверка всех адресов исключает round-robin на private IP.
  def safe_uri?(uri)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.port == 443 && public_addresses(uri.host).any?
  end

  def public_addresses(host)
    addresses = Resolv.getaddresses(host).uniq
    return [] if addresses.empty?

    parsed = addresses.map { |address| IPAddr.new(address) }
    return [] if parsed.any? { |address| FORBIDDEN_NETWORKS.any? { |network| network.include?(address) } }

    addresses
  rescue StandardError
    []
  end

  def meta(html, property)
    html[/<meta[^>]+property=["']#{Regexp.escape(property)}["'][^>]+content=["']([^"']*)["']/i, 1] ||
      html[/<meta[^>]+content=["']([^"']*)["'][^>]+property=["']#{Regexp.escape(property)}["']/i, 1]
  end

  def meta_name(html, name)
    html[/<meta[^>]+name=["']#{Regexp.escape(name)}["'][^>]+content=["']([^"']*)["']/i, 1]
  end

  def clean(value)
    return if value.blank?

    CGI.unescapeHTML(value.gsub(/<[^>]*>/, "")).squeeze(" ").strip.truncate(200).presence
  end

  def absolute_url(page_url, image_url)
    return if image_url.blank?

    uri = URI.join(page_url, image_url)
    uri.to_s if safe_uri?(uri)
  rescue URI::Error
    nil
  end
end
