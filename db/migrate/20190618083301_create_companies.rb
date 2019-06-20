class CreateCompanies < ActiveRecord::Migration[5.2]
  def change
    create_table :companies do |t|
      t.string :name
      t.boolean :use_agency, null: false, default: true

      t.timestamps
    end
  end
end
