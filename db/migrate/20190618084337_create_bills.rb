class CreateBills < ActiveRecord::Migration[5.2]
  def change
    create_table :bills do |t|
      t.string :state
      t.string :billing_agency_state
      t.string :payment_method
      t.integer :price
      t.date :bill_on
      t.references :company, foreign_key: true
      t.references :orderer, foreign_key: true
      t.references :order, foreign_key: true

      t.timestamps
    end
  end
end
