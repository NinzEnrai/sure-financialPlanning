# frozen_string_literal: true

# Before this merge, version 20261012120000 belonged to this fork's
# create_planning_settings migration and production recorded it as applied.
# Upstream later published 20261012120000_add_statement_cycle_to_credit_cards,
# so a database upgraded from the fork's history treats that migration as
# already applied and skips its two columns. Re-apply them here; fresh
# databases get the columns from the upstream migration or db/schema.rb and the
# guards make this a no-op.
class HealCreditCardStatementCycleColumns < ActiveRecord::Migration[8.1]
  def up
    add_column :credit_cards, :statement_close_day, :integer unless column_exists?(:credit_cards, :statement_close_day)
    add_column :credit_cards, :due_day, :integer unless column_exists?(:credit_cards, :due_day)

    unless check_constraint_exists?(:credit_cards, name: "chk_credit_cards_statement_close_day")
      add_check_constraint :credit_cards, "statement_close_day BETWEEN 1 AND 31",
                           name: "chk_credit_cards_statement_close_day"
    end

    unless check_constraint_exists?(:credit_cards, name: "chk_credit_cards_due_day")
      add_check_constraint :credit_cards, "due_day BETWEEN 1 AND 31",
                           name: "chk_credit_cards_due_day"
    end
  end

  # Nothing to undo: these columns belong to the upstream migration, so
  # rolling this heal back must not remove them.
  def down; end
end
