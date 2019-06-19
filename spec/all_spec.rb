require 'rails_helper'

RSpec.describe '全部' do
  let(:元請) { Company.create!(name: '元請') }
  let(:下請) { Company.create!(name: '下請') }
  let(:プラットフォーム) { Company.create!(name: 'プラットフォーム') }

  def step(action, who, what = nil, options = nil)
    p [action, who.name, what.try(:name) || what.to_s, options]

    if respond_to?(action)
      self.send(action, who, what, options)
    end
  end

  def 元請が発注を作成(_, _, _)
    Order.create!(company: 下請, orderer: 元請)
  end

  def 元請が発注を送信(_, order, _)
    order.receive!
  end

  def 下請が発注を承認(_, order, _)
    Order.transaction do
      order.accept!
      order.bills.create(
        payment_method: 'invoice',
        orderer: order.orderer,
        company: order.company
        )
    end
  end

  def 下請が支払方法を選択(_, bill, options = {})
    bill.update(payment_method: options[:payment_method])
  end

  def 下請が着工報告(_, order, _)
    order.start!
  end

  def 下請が完工報告(_, order, _)
    order.complete!
  end

  def 元請が完工を承認(_, order, _)
    order.approve!
  end

  def 元請が請求金額を入力(_, bill, options)
    bill.update(price: options[:price])
  end

  def 元請が金額確定(_, bill, options)
    Bill.transaction do
      bill.determine!
      bill.update(bill_on: options[:bill_on])
    end
  end

  def 下請が請求を確定(_, bill, _)
    Bill.transaction do
      bill.bill!
      bill.wait!

      # プラットフォーム => 下請
      bill.receivables.create(
        orderer: プラットフォーム,
        company: 下請,
        price: bill.price,
        pay_on: (bill.bill_on + 1.month).end_of_month
      )

      # 元請 => プラットフォーム
      bill.receivables.create(
        orderer: 元請,
        company: プラットフォーム,
        price: bill.price,
        pay_on: (bill.bill_on + 1.month).end_of_month
      )
    end
  end

  def プラットフォームが元請へ請求書送付(_, bill, _)
    bill.send_bill!
  end

  def 元請がプラットフォームへの入金指示(_, receivable, _)
    receivable.pay!
  end

  def プラットフォームが支払予定取り込み(_, _, _)
    # NOTE: 実装の簡便のため、「orderer がプラットフォーム」で「state が入金予定」の支払予定をすべて更新する
    Receivable.where(orderer: プラットフォーム, state: 'will_pay').update(state: 'paid')
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
      construction_state: 'not_started'

    step '元請が発注を送信', 元請, 発注

    check 発注,
      state: 'received',
      construction_state: 'not_started'

    step '下請が発注を承認', 下請, 発注

    check 発注,
      state: 'accepted',
      construction_state: 'not_started'

    支払依頼1 = 発注.bills.first

    check 支払依頼1,
      state: 'undetermined',
      billing_agency_state: 'none',
      payment_method: 'invoice',
      price: nil,
      bill_on: nil

    step '下請が支払方法を選択', 下請, 支払依頼1, payment_method: 'invoice'

    check 支払依頼1,
      state: 'undetermined',
      payment_method: 'invoice'

    step '下請が着工報告', 下請, 発注

    check 発注,
      construction_state: 'started'

    step '下請が完工報告', 下請, 発注

    check 発注,
      construction_state: 'completed'

    step '元請が完工を承認', 元請, 発注

    check 発注,
      construction_state: 'completion_approved'

    step '元請が請求金額を入力', 元請, 支払依頼1, price: 30_000

    check 支払依頼1,
      price: 30_000

    step '元請が金額確定', 元請, 支払依頼1, bill_on: Date.today

    check 支払依頼1,
      state: 'determined',
      price: 30_000,
      bill_on: Date.today


    step '下請が請求を確定', 下請, 支払依頼1,
      orderer: 元請,
      company: 下請,
      pay_on: (支払依頼1.bill_on + 1.month).end_of_month

    check 支払依頼1,
      state: 'billed',
      billing_agency_state: 'waiting'

    支払1 = 支払依頼1.receivables.first
    支払2 = 支払依頼1.receivables.last

    check 支払1,
      state: 'will_pay',
      orderer: プラットフォーム,
      company: 下請,
      price: 30_000,
      pay_on: (支払依頼1.bill_on + 1.month).end_of_month

    check 支払2,
      state: 'will_pay',
      orderer: 元請,
      company: プラットフォーム,
      price: 30_000,
      pay_on: (支払依頼1.bill_on + 1.month).end_of_month

    step 'プラットフォームが元請へ請求書送付', プラットフォーム, 支払依頼1

    check 支払依頼1,
      state: 'billed',
      billing_agency_state: 'sent'

    # NOTE: システム上では特に行うことは無いため、コメントアウト
    # step 'プラットフォームが入金予定取り込み', プラットフォーム

    step '元請がプラットフォームへの入金指示', 元請, 支払2

    check 支払2.reload,
      state: 'paid'

    step 'プラットフォームが支払予定取り込み', プラットフォーム

    check 支払1.reload,
      state: 'paid'
  end
end
