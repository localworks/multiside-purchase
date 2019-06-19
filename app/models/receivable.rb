class Receivable < ApplicationRecord
  include AASM

  belongs_to :orderer, class_name: 'Company'
  belongs_to :company

  aasm(:state) do
    state :will_pay, initial: true
    state :paid

    event :pay do
      transitions to: :paid, from: :will_pay
    end
  end
end
