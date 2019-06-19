class Order < ApplicationRecord
  include AASM

  belongs_to :orderer, class_name: 'Company'
  belongs_to :company

  has_many :bills

  aasm(:state) do
    state :created, initial: true
    state :received # 発注依頼済 # FIXME: state 名を変えたい
    state :accepted # 発注承認済

    event :receive do
      transitions to: :received, from: :created
    end

    event :accept do
      transitions to: :accepted, from: :received
    end
  end

  aasm(:construction_state) do
    state :not_started, initial: true
    state :started
    state :completed
    state :completion_approved

    event :start do
      transitions to: :started, from: :not_started
    end

    event :complete do
      transitions to: :completed, from: :started
    end

    event :approve do
      transitions to: :completion_approved, from: :completed
    end
  end

  # before_create ->(order) { order.construction_state = 'not_started' }

  def name
    "発注#{id}"
  end
end
