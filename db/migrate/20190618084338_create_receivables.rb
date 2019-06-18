class CreateReceivables < ActiveRecord::Migration[5.2]
  def change
    create_table :receivables do |t|
      t.string :state
      t.integer :price
      t.date :pay_on
      t.references :company, foreign_key: true
      t.references :orderer, foreign_key: true

      t.timestamps
    end
  end
end
