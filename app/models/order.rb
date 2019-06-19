class Order < ApplicationRecord
  include ActiveModel::Transitions

  belongs_to :orderer, class_name: 'Company'
  belongs_to :company

  has_many :bills

  state_machine attribute_name: :state do
    state :created
    state :received # 発注依頼済 # FIXME: state 名を変えたい
    state :accepted # 発注承認済

    event :receive do
      transitions to: :received, from: :created
    end

    event :accept do
      transitions to: :accepted, from: :received
    end
  end

  before_create ->(order) { order.construction_state = 'not_started' }

  def name
    "発注#{id}"
  end
end
