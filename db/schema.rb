# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_15_094000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_db_files", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "data", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_active_storage_db_files_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "chat_folder_rooms", force: :cascade do |t|
    t.integer "chat_folder_id", null: false
    t.datetime "created_at", null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_folder_id", "room_id"], name: "index_chat_folder_rooms_on_chat_folder_id_and_room_id", unique: true
    t.index ["chat_folder_id"], name: "index_chat_folder_rooms_on_chat_folder_id"
    t.index ["room_id"], name: "index_chat_folder_rooms_on_room_id"
  end

  create_table "chat_folders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "position"], name: "index_chat_folders_on_user_id_and_position"
    t.index ["user_id"], name: "index_chat_folders_on_user_id"
  end

  create_table "message_attachments", force: :cascade do |t|
    t.integer "byte_size", default: 0, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "filename", null: false
    t.integer "height"
    t.string "kind", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.text "waveform"
    t.integer "width"
    t.index ["message_id"], name: "index_message_attachments_on_message_id"
  end

  create_table "message_mentions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id", "user_id"], name: "index_message_mentions_on_message_id_and_user_id", unique: true
    t.index ["message_id"], name: "index_message_mentions_on_message_id"
    t.index ["user_id", "message_id"], name: "index_message_mentions_on_user_id_and_message_id"
    t.index ["user_id"], name: "index_message_mentions_on_user_id"
  end

  create_table "message_reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id", "user_id", "emoji"], name: "index_message_reactions_on_message_id_and_user_id_and_emoji", unique: true
    t.index ["message_id"], name: "index_message_reactions_on_message_id"
    t.index ["user_id"], name: "index_message_reactions_on_user_id"
  end

  create_table "message_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id", "user_id"], name: "index_message_views_on_message_id_and_user_id", unique: true
    t.index ["message_id"], name: "index_message_views_on_message_id"
    t.index ["user_id"], name: "index_message_views_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "edited_at"
    t.datetime "expires_at"
    t.string "forwarded_from_external_id"
    t.string "forwarded_from_name"
    t.text "link_preview"
    t.datetime "pinned_at"
    t.text "plain_body"
    t.text "quote_text"
    t.integer "reply_to_id"
    t.integer "room_id", null: false
    t.boolean "silent", default: false, null: false
    t.integer "thread_root_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "view_once", default: false, null: false
    t.index ["expires_at"], name: "index_messages_on_expires_at"
    t.index ["reply_to_id"], name: "index_messages_on_reply_to_id"
    t.index ["room_id", "pinned_at"], name: "index_messages_on_room_id_and_pinned_at"
    t.index ["room_id"], name: "index_messages_on_room_id"
    t.index ["thread_root_id", "id"], name: "index_messages_on_thread_root_id_and_id"
    t.index ["thread_root_id"], name: "index_messages_on_thread_root_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "room_memberships", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.datetime "marked_unread_at"
    t.datetime "muted_at"
    t.datetime "pinned_at"
    t.integer "room_id", null: false
    t.string "theme"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "visible", default: true, null: false
    t.index ["room_id", "user_id"], name: "index_room_memberships_on_room_id_and_user_id", unique: true
    t.index ["room_id"], name: "index_room_memberships_on_room_id"
    t.index ["user_id", "archived_at"], name: "index_room_memberships_on_user_id_and_archived_at"
    t.index ["user_id", "pinned_at"], name: "index_room_memberships_on_user_id_and_pinned_at"
    t.index ["user_id", "visible"], name: "index_room_memberships_on_user_id_and_visible"
    t.index ["user_id"], name: "index_room_memberships_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "dm_key"
    t.string "invite_token"
    t.string "name"
    t.integer "owner_id"
    t.integer "parent_id"
    t.integer "saved_for_id"
    t.integer "ttl_seconds"
    t.datetime "updated_at", null: false
    t.index ["dm_key"], name: "index_rooms_on_dm_key", unique: true
    t.index ["invite_token"], name: "index_rooms_on_invite_token", unique: true
    t.index ["owner_id"], name: "index_rooms_on_owner_id"
    t.index ["parent_id"], name: "index_rooms_on_parent_id"
    t.index ["saved_for_id"], name: "index_rooms_on_saved_for_id", unique: true
  end

  create_table "scheduled_messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "deliver_at", null: false
    t.datetime "delivered_at"
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["deliver_at"], name: "index_scheduled_messages_on_deliver_at"
    t.index ["room_id"], name: "index_scheduled_messages_on_room_id"
    t.index ["user_id", "deliver_at"], name: "index_scheduled_messages_on_user_id_and_deliver_at"
    t.index ["user_id"], name: "index_scheduled_messages_on_user_id"
  end

  create_table "starred_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id"], name: "index_starred_messages_on_message_id"
    t.index ["user_id", "created_at"], name: "index_starred_messages_on_user_id_and_created_at"
    t.index ["user_id", "message_id"], name: "index_starred_messages_on_user_id_and_message_id", unique: true
    t.index ["user_id"], name: "index_starred_messages_on_user_id"
  end

  create_table "user_blocks", force: :cascade do |t|
    t.integer "blocked_id", null: false
    t.integer "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_user_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_user_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_user_blocks_on_blocker_id"
    t.check_constraint "blocker_id <> blocked_id", name: "user_blocks_distinct_users"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.string "chat_status", default: "online", null: false
    t.text "chat_status_text", default: "В сети", null: false
    t.datetime "created_at", null: false
    t.string "external_id"
    t.datetime "last_seen_at"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_users_on_external_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chat_folder_rooms", "chat_folders"
  add_foreign_key "chat_folder_rooms", "rooms"
  add_foreign_key "chat_folders", "users"
  add_foreign_key "message_attachments", "messages"
  add_foreign_key "message_mentions", "messages"
  add_foreign_key "message_mentions", "users"
  add_foreign_key "message_reactions", "messages"
  add_foreign_key "message_reactions", "users"
  add_foreign_key "message_views", "messages"
  add_foreign_key "message_views", "users"
  add_foreign_key "messages", "messages", column: "reply_to_id"
  add_foreign_key "messages", "messages", column: "thread_root_id"
  add_foreign_key "messages", "rooms"
  add_foreign_key "messages", "users"
  add_foreign_key "room_memberships", "rooms"
  add_foreign_key "room_memberships", "users"
  add_foreign_key "rooms", "users", column: "saved_for_id"
  add_foreign_key "scheduled_messages", "rooms"
  add_foreign_key "scheduled_messages", "users"
  add_foreign_key "starred_messages", "messages"
  add_foreign_key "starred_messages", "users"
  add_foreign_key "user_blocks", "users", column: "blocked_id"
  add_foreign_key "user_blocks", "users", column: "blocker_id"
end
