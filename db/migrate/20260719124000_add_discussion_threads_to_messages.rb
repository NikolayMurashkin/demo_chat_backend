# frozen_string_literal: true

class AddDiscussionThreadsToMessages < ActiveRecord::Migration[8.1]
  def change
    # Сообщения discussion-треда остаются в той же комнате, но не попадают в её общую ленту.
    # Корнем может быть только обычное сообщение (thread_root_id = NULL).
    add_reference :messages, :thread_root, foreign_key: {to_table: :messages}
    add_index :messages, %i[thread_root_id id]
  end
end
