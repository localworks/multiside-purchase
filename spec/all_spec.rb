require 'rails_helper'

RSpec.describe '全部' do
  let(:元請) { Company.create!(name: '元請') }
  let(:下請) { Company.create!(name: '下請') }
  let(:プラットフォーム) { Company.create!(name: 'プラットフォーム') }
  let(:元請_決済代行なし) { Company.create!(name: '元請(決済代行なし)', use_agency: false) }

  def step(action, who, what = nil, options = {})
    p [action, who.name, what.try(:name) || what.to_s, options]

    if respond_to?(action)
      self.send(action, who, what, options)
    end
  end

  def 元請が発注を作成(orderer, _, options)
    Order.create!(
      orderer: orderer,
      company: options[:company],
      price: options[:price])
  end

  def 元請が発注を送信(_, order, _)
    order.receive!
  end

  def 下請が発注を承認(_, order, _)
    Order.transaction do
      order.accept!
      order.bills.create(
        payment_method: 'invoice',
        price: order.price,
        orderer: order.orderer,
        company: order.company
        )
    end
  end

  def 下請が支払方法を選択(_, bill, options = {})
    bill.update(payment_method: options[:payment_method])
  end

  def 下請が着工報告(_, order, _)
    Order.transaction do
      order.start!
      bill = order.bills.last
      if bill.payment_method == 'start_and_complete'
        bill.receivables.create(
          orderer: プラットフォーム,
          company: order.company,
          price: (bill.price * 0.3 * 0.95).ceil,
          pay_on: Time.zone.today
        )
      end
    end
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

      pay_price = nil
      receive_price = nil
      pay_on = nil
      if bill.payment_method == 'start_and_complete'
        # TODO: 本番では厳密な計算を実装する
        pay_price = (bill.price * 0.7 * 0.95).ceil
        receive_price = bill.price
        pay_on = bill.bill_on
      elsif bill.payment_method == 'complete'
        pay_price = (bill.price * 0.95).ceil
        receive_price = bill.price
        pay_on = bill.bill_on
      elsif bill.payment_method == 'invoice'
        pay_price = receive_price = bill.price
        pay_on = (bill.bill_on + 1.month).end_of_month
      end

      # 決済代行なしの場合は元請から下請への支払いレコードを作成して終了
      unless bill.orderer.use_agency
        bill.receivables.create(
          orderer: bill.orderer,
          company: bill.company,
          price: pay_price,
          pay_on: pay_on
        )
        return
      end

      bill.wait!

      # プラットフォーム => 下請
      bill.receivables.create(
        orderer: プラットフォーム,
        company: bill.company,
        price: pay_price,
        pay_on: pay_on
      )

      # 元請 => プラットフォーム
      bill.receivables.create(
        orderer: bill.orderer,
        company: プラットフォーム,
        price: receive_price,
        pay_on: pay_on
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

  def 元請が下請への入金指示(_, receivable, _)
    receivable.pay!
  end

  def check(what, options = {})
    options.each do |key, value|
      expect(what.send(key)).to eq value
    end
  end

  it 'CASE1' do
    step '元請が発注を作成', 元請, nil, company: 下請

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

    step '下請が請求を確定', 下請, 支払依頼1

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

  it 'CASE3' do
    step '元請が発注を作成', 元請_決済代行なし, nil, company: 下請

    発注 = Order.first

    check 発注,
      state: 'created',
      construction_state: 'not_started'

    step '元請が発注を送信', 元請_決済代行なし, 発注

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

    # NOTE: 決済代行がない場合、支払方法は通常サイト確定
    # UIでどうするかは別途確認

    check 支払依頼1,
      state: 'undetermined',
      payment_method: 'invoice'

    step '下請が着工報告', 下請, 発注

    check 発注,
      construction_state: 'started'

    step '下請が完工報告', 下請, 発注

    check 発注,
      construction_state: 'completed'

    step '元請が完工を承認', 元請_決済代行なし, 発注

    check 発注,
      construction_state: 'completion_approved'

    step '元請が請求金額を入力', 元請_決済代行なし, 支払依頼1, price: 30_000

    check 支払依頼1,
      price: 30_000

    step '元請が金額確定', 元請_決済代行なし, 支払依頼1, bill_on: Time.zone.today

    check 支払依頼1,
      state: 'determined',
      price: 30_000,
      bill_on: Time.zone.today

    step '下請が請求を確定', 下請, 支払依頼1

    check 支払依頼1,
      state: 'billed',
      billing_agency_state: 'none'

    支払1 = 支払依頼1.receivables.first

    check 支払1,
      state: 'will_pay',
      orderer: 元請_決済代行なし,
      company: 下請,
      price: 30_000,
      pay_on: (支払依頼1.bill_on + 1.month).end_of_month

    # NOTE: システム上では特に行うことは無いため、コメントアウト
    # step '下請が元請へ請求書送付', 下請, 支払依頼1

    step '元請が下請への入金指示', 元請_決済代行なし, 支払1

    check 支払1,
      state: 'paid'
  end

  it 'CASE4' do
    step '元請が発注を作成', 元請, nil, company: 下請

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

    step '下請が支払方法を選択', 下請, 支払依頼1, payment_method: 'complete'

    check 支払依頼1,
      state: 'undetermined',
      price: nil,
      payment_method: 'complete'

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

    step '元請が金額確定', 元請, 支払依頼1, bill_on: Time.zone.today

    check 支払依頼1,
      state: 'determined',
      price: 30_000,
      bill_on: Time.zone.today

    step '下請が請求を確定', 下請, 支払依頼1

    check 支払依頼1,
      state: 'billed',
      billing_agency_state: 'waiting'

    支払1 = 支払依頼1.receivables.first
    支払2 = 支払依頼1.receivables.last

    check 支払1,
      state: 'will_pay',
      orderer: プラットフォーム,
      company: 下請,
      price: 28_500,
      pay_on: Time.zone.today

    check 支払2,
      state: 'will_pay',
      orderer: 元請,
      company: プラットフォーム,
      price: 30_000,
      pay_on: Time.zone.today

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

  it 'CASE5' do
    step '元請が発注を作成', 元請, nil,
      company: 下請,
      price: 30_000

    発注 = Order.first

    check 発注,
      state: 'created',
      price: 30_000,
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
      price: 30_000,
      bill_on: nil

    step '下請が支払方法を選択', 下請, 支払依頼1, payment_method: 'start_and_complete'

    check 支払依頼1,
      state: 'undetermined',
      price: 30_000,
      payment_method: 'start_and_complete'

    step '下請が着工報告', 下請, 発注

    check 発注,
      construction_state: 'started'

    支払1 = 支払依頼1.receivables.first

    check 支払1,
      state: 'will_pay',
      orderer: プラットフォーム,
      company: 下請,
      price: 8550,
      pay_on: Time.zone.today

    step 'プラットフォームが支払予定取り込み', プラットフォーム

    check 支払1.reload,
      state: 'paid'

    step '下請が完工報告', 下請, 発注

    check 発注,
      construction_state: 'completed'

    step '元請が完工を承認', 元請, 発注

    check 発注,
      construction_state: 'completion_approved'


    step '元請が金額確定', 元請, 支払依頼1, bill_on: Date.today

    check 支払依頼1,
      state: 'determined',
      price: 30_000,
      bill_on: Date.today

    step '下請が請求を確定', 下請, 支払依頼1

    check 支払依頼1,
      state: 'billed',
      billing_agency_state: 'waiting'

    支払2 = 支払依頼1.receivables[1] # TODO: ちゃんとした絞り込みが必要そう
    支払3 = 支払依頼1.receivables[2]

    check 支払2,
      state: 'will_pay',
      orderer: プラットフォーム,
      company: 下請,
      price: 19_950,
      pay_on: Time.zone.today

    check 支払3,
      state: 'will_pay',
      orderer: 元請,
      company: プラットフォーム,
      price: 30_000,
      pay_on: Time.zone.today


    step 'プラットフォームが元請へ請求書送付', プラットフォーム, 支払依頼1

    check 支払依頼1,
      state: 'billed',
      billing_agency_state: 'sent'

    # NOTE: システム上では特に行うことは無いため、コメントアウト
    # step 'プラットフォームが入金予定取り込み', プラットフォーム

    step '元請がプラットフォームへの入金指示', 元請, 支払3

    check 支払3.reload,
      state: 'paid'

    step 'プラットフォームが支払予定取り込み', プラットフォーム

    check 支払2.reload,
      state: 'paid'
  end
end
