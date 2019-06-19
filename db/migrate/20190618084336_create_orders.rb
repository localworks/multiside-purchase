class CreateOrders < ActiveRecord::Migration[5.2]
  def change
    create_table :orders do |t|
      t.string :state
      t.string :construction_state
      t.integer :price
      t.references :company, foreign_key: true
      t.references :orderer, foreign_key: true

      t.timestamps
    end
  end
end
