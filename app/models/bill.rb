class Bill < ApplicationRecord
  include AASM

  belongs_to :company
  belongs_to :orderer, class_name: 'Company'
  has_many :receivables

  aasm(:state) do
    state :undetermined, initial: true # 金額確定待ち
    state :determined                  # 金額確定済
    state :billed                      # 請求済

    event :determine do
      transitions to: :determined, from: :undetermined
    end

    event :bill do
      transitions to: :billed, from: :determined
    end
  end

  # 請求代行ステート
  aasm(:billing_agency_state) do
    state :none, initial: true # なし
    state :waiting             # 請求書送付待ち
    state :sent                # 請求書送付済

    event :wait do
      transitions to: :waiting, from: :none
    end

    event :send_bill do
      transitions to: :sent, from: :waiting
    end
  end
end
