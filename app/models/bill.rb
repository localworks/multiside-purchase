class Bill < ApplicationRecord
  belongs_to :company
  belongs_to :orderer, class_name: 'Company'
  has_many :receivables
end
