class Order < ApplicationRecord
  include ActiveModel::Transitions

  belongs_to :orderer, class_name: 'Company'
  belongs_to :company

  state_machine attribute_name: :state do
    state :created
    state :received # 発注依頼済 # FIXME: state 名を変えたい

    event :receive do
      transitions to: :received, from: :created

    end
  end

  before_create ->(order) { order.shipping_state = 'unsent' } # 未発送

  def name
    "発注#{id}"
  end
end
