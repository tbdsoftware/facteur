# frozen_string_literal: true

RSpec.describe Facteur::Mailing do
  it 'schedules its delivery once created' do
    mailing = described_class.create!(mailer_klass: 'TestMailer', mailer_method: 'welcome',
                                      mailer_params: ['jane@facteur.test'])

    expect(Facteur::MailingDeliveryJob.jobs.map { |job| job['args'] }).to eq([[mailing.id]])
    expect(mailing).to be_current_status_pending
  end
end
