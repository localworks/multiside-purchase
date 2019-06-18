class CreateInvoices < ActiveRecord::Migration[5.2]
  def change
    create_table :invoices do |t|
      t.string :state
      t.string :payment_method
      t.integer :price
      t.date :bill_on

      t.timestamps
    end
  end
end
