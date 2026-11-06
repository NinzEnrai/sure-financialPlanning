class AddEntryableLookupIndexToEntries < ActiveRecord::Migration[8.1]
  # The transaction list looks page rows up by polymorphic entryable id, and the
  # transfer-hint query drives from exactly those ids. Without this index that
  # lookup is a sequential scan once a family has a large ledger.
  disable_ddl_transaction!

  def change
    unless index_exists?(:entries, [ :entryable_type, :entryable_id ], name: "index_entries_on_entryable_type_and_id")
      add_index :entries, [ :entryable_type, :entryable_id ],
        name: "index_entries_on_entryable_type_and_id",
        algorithm: :concurrently
    end
  end
end
