class Invoice < ApplicationRecord
  belongs_to :orderer, class_name: 'Company'
  belongs_to :company
end
