class Receivable < ApplicationRecord
  belongs_to :orderer
  belongs_to :company
end
