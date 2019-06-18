class Invoice < ApplicationRecord
  belongs_to :orderer
  belongs_to :company
end
