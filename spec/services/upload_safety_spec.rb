# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe UploadSafety do
  def uploaded_file(contents:, filename:, content_type:)
    tempfile = Tempfile.new("chat-upload")
    tempfile.binmode
    tempfile.write(contents)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: content_type,
    )
  end

  it "accepts a supported text attachment and normalizes its filename" do
    upload = uploaded_file(contents: "hello", filename: "notes.txt", content_type: "text/plain")

    result = described_class.inspect!(upload, max_bytes: 10.bytes)

    expect(result).to have_attributes(filename: "notes.txt", content_type: "text/plain", byte_size: 5)
  ensure
    upload&.tempfile&.close!
  end

  it "rejects active HTML even when it is hidden after a benign prefix" do
    upload = uploaded_file(
      contents: ("a" * UploadSafety::SNIFF_BYTES) + "<script>alert(1)</script>",
      filename: "notes.txt",
      content_type: "text/plain",
    )

    expect { described_class.inspect!(upload, max_bytes: 1.kilobyte) }
      .to raise_error(UploadSafety::UnsafeUpload, "invalid_file_signature")
  ensure
    upload&.tempfile&.close!
  end

  it "rejects active HTML declared as an image" do
    upload = uploaded_file(contents: "<script>alert(1)</script>", filename: "photo.png", content_type: "image/png")

    expect { described_class.inspect!(upload, max_bytes: 1.kilobyte) }
      .to raise_error(UploadSafety::UnsafeUpload, "invalid_file_signature")
  ensure
    upload&.tempfile&.close!
  end

  it "accepts a MediaRecorder WebM MIME type with codec parameters" do
    upload = uploaded_file(
      contents: "\x1A\x45\xDF\xA3".b + ("\0".b * 32),
      filename: "voice-message.webm",
      content_type: "audio/webm;codecs=opus",
    )

    result = described_class.inspect!(upload, max_bytes: 1.kilobyte)

    expect(result.content_type).to eq("audio/webm")
  ensure
    upload&.tempfile&.close!
  end
end
