require 'rails_helper'

RSpec.describe '全部' do
  let(:元請) { Company.create!(name: '元請') }
  let(:下請) { Company.create!(name: '下請') }

  def step(action, who, what = nil)
    p [action, who.name, what&.name]

    if respond_to?(action)
      self.send(action, who, what)
    end
  end

  def 元請が発注を作成(_, _)
    Order.create!(company: 下請, orderer: 元請)
  end

  def 元請が発注を送信(_, order)
    order.receive!
  end

  def check(what, options = {})
    options.each do |key, value|
      expect(what.send(key)).to eq value
    end
  end

  it 'CASE1' do
    step '元請が発注を作成', 元請

    発注 = Order.first

    check 発注,
      state: 'created',
      shipping_state: 'unsent'

    step '元請が発注を送信', 元請, 発注

    check 発注,
      state: 'received', 
      shipping_state: 'unsent'

    step '下請けが発注を承認', 下請, 発注
    step '下請が支払方法を選択', 下請, 発注
    step '下請が着工報告', 下請, 発注
    step '下請が完工報告', 下請, 発注
    step '元請が完工を承認', 下請, 発注
  end
end
