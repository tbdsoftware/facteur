# frozen_string_literal: true

RSpec.describe Facteur::Scaleway::VerifyTopicService do
  let(:envelope) { fixture_envelope('02_notification_email_queued.json') }
  let(:foreign_topic_arn) { 'arn:scw:sns:fr-par:project-00000000-0000-0000-0000-000000000000:someone-else' }

  def verify(envelope)
    described_class.new(envelope).call
  end

  before { allow(Rails.logger).to receive(:warn) }

  it 'accepts a message from an allowed topic' do
    Facteur.scaleway_topic_arns = [foreign_topic_arn, SnsHelpers::TOPIC_ARN]

    expect(verify(envelope)).to be(true)
    expect(Rails.logger).not_to have_received(:warn)
  end

  it 'refuses a message from another topic and logs it' do
    Facteur.scaleway_topic_arns = [SnsHelpers::TOPIC_ARN]

    expect(verify(envelope.merge('TopicArn' => foreign_topic_arn))).to be(false)
    expect(Rails.logger).to have_received(:warn)
      .with(/Facteur.scaleway_topic_arns does not include "#{Regexp.escape(foreign_topic_arn)}"/)
  end

  it 'refuses a message without TopicArn' do
    Facteur.scaleway_topic_arns = [SnsHelpers::TOPIC_ARN]

    expect(verify(envelope.except('TopicArn'))).to be(false)
  end

  it 'compares the whole ARN, case included' do
    Facteur.scaleway_topic_arns = [SnsHelpers::TOPIC_ARN]

    expect(verify(envelope.merge('TopicArn' => SnsHelpers::TOPIC_ARN.upcase))).to be(false)
    expect(verify(envelope.merge('TopicArn' => "#{SnsHelpers::TOPIC_ARN}-2"))).to be(false)
  end

  it 'refuses every message when no topic is allowed, and names the setting' do
    Facteur.scaleway_topic_arns = []

    expect(verify(envelope)).to be(false)
    expect(Rails.logger).to have_received(:warn).with(/Facteur.scaleway_topic_arns is empty/)
  end

  it 'accepts a single ARN configured as a String' do
    Facteur.scaleway_topic_arns = SnsHelpers::TOPIC_ARN

    expect(verify(envelope)).to be(true)
  end
end
