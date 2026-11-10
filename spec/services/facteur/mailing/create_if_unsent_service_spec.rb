# frozen_string_literal: true

RSpec.describe Facteur::Mailing::CreateIfUnsentService do
  def create_if_unsent(**attributes)
    described_class.new({ mailer_klass: 'TestMailer', mailer_method: 'welcome' }.merge(attributes)).call
  end

  it 'creates the mailing the first time' do
    mailing = nil

    expect { mailing = create_if_unsent(mailer_params: ['jane@facteur.test']) }.to change(Facteur::Mailing, :count).by(1)
    expect(mailing).to be_persisted
  end

  it 'returns the existing mailing for the same attributes, without creating another one' do
    existing = create_if_unsent(mailer_params: ['jane@facteur.test'])

    expect { expect(create_if_unsent(mailer_params: ['jane@facteur.test'])).to eq(existing) }
      .not_to change(Facteur::Mailing, :count)
  end

  it 'creates another mailing for other mailer_params, another mailer method or another resource' do
    existing = create_if_unsent(mailer_params: ['jane@facteur.test'])

    others = [
      create_if_unsent(mailer_params: ['john@facteur.test']),
      create_if_unsent(mailer_method: 'notification', mailer_params: ['jane@facteur.test']),
      create_if_unsent(mailer_params: ['jane@facteur.test'], resource: existing)
    ]

    expect(others).to all(be_persisted)
    expect((others + [existing]).map(&:id).uniq.size).to eq(4)
  end

  it 'matches parameterized mailer params whatever the type of their keys' do
    existing = create_if_unsent(mailer_method: 'notification', mailer_params: { 'to' => 'jane@facteur.test' })

    expect(create_if_unsent(mailer_method: 'notification', mailer_params: { to: 'jane@facteur.test' })).to eq(existing)
  end

  it 'considers a mailing sent when its stored mailer_params contain the requested ones' do
    existing = create_if_unsent(mailer_params: ['jane@facteur.test', 'Welcome back'])

    expect(create_if_unsent(mailer_params: ['jane@facteur.test'])).to eq(existing)
    expect(create_if_unsent(mailer_params: ['jane@facteur.test', 'Welcome back', 'extra'])).not_to eq(existing)
  end
end
