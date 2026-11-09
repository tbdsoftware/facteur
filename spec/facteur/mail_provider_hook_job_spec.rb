# frozen_string_literal: true

RSpec.describe Facteur::MailProviderHookJob do
  let(:mailing) do
    Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'welcome', mailer_params: ['jane@facteur.test'],
                             to: 'jane@facteur.test', sent_at: Time.current)
  end

  def perform(provider, params)
    described_class.new.perform(provider, params)
  end

  def replay(*fixtures, mailing_id: mailing.id)
    fixtures.each { |fixture| perform('scaleway', event_payload(fixture, mailing_id)) }
    mailing.reload
  end

  def with_type(payload, type)
    payload.merge('type' => type, 'id' => SecureRandom.uuid)
  end

  let(:mailbox_not_found_reason) do
    event_payload('05_notification_email_mailbox_not_found.json')['email_response_message'].strip
  end

  it 'delegates to MailProviderHookService' do
    service = instance_double(Facteur::MailProviderHookService, call: nil)
    allow(Facteur::MailProviderHookService).to receive(:new).with('scaleway', { 'id' => '1' }).and_return(service)

    perform('scaleway', { 'id' => '1' })

    expect(service).to have_received(:call)
  end

  describe 'Scaleway TEM events' do
    it 'maps email_queued to processed' do
      replay('02_notification_email_queued.json')

      expect(mailing).to be_current_status_processed
      expect(mailing.processed_at).to eq(Time.zone.iso8601('2026-11-09T03:01:28.066687Z'))
      expect(mailing.events.first).to include(
        'event' => 'processed', 'type' => 'email_queued', 'provider' => 'scaleway', 'reason' => nil,
        'provider_event_id' => 'af6d2457-c137-4dfe-b772-a8c269b3e720',
        'provider_message_id' => 'eeecec74-a810-4a8a-b792-0ca83f0d822e',
        'timestamp' => Time.zone.iso8601('2026-11-09T03:01:28.066687Z').to_f
      )
      expect(mailing.events.first['payload']).to eq(event_payload('02_notification_email_queued.json', mailing.id))
      expect(mailing.events.first).not_to have_key('datetime')
    end

    it 'maps email_delivered to delivered' do
      replay('02_notification_email_queued.json', '03_notification_email_delivered.json')

      expect(mailing).to be_current_status_delivered
      expect(mailing.processed_at).to be_present
      expect(mailing.delivered_at).to eq(Time.zone.iso8601(event_payload('03_notification_email_delivered.json')['created_at']))
      expect(mailing.error_at).to be_nil
    end

    it 'records email_deferred without changing the status' do
      replay('02_notification_email_queued.json')
      perform('scaleway', with_type(event_payload('02_notification_email_queued.json', mailing.id), 'email_deferred'))

      mailing.reload
      expect(mailing).to be_current_status_processed
      expect(mailing.events.map { |e| e['event'] }).to eq(%w[processed deferred])
      expect(mailing.error_at).to be_nil
    end

    %w[email_dropped email_spam email_mailbox_not_found email_blocklisted].each do |type|
      it "maps #{type} to an error with '#{type}: reason'" do
        payload = with_type(event_payload('05_notification_email_mailbox_not_found.json', mailing.id), type)

        perform('scaleway', payload)

        mailing.reload
        expect(mailing).to be_current_status_error
        expect(mailing.error_msg).to eq("#{type}: #{mailbox_not_found_reason}")
        expect(mailing.error_at).to eq(Time.zone.iso8601(payload['created_at']))
        expect(mailing.events.first).to include('event' => 'dropped', 'type' => type)
      end
    end

    it 'falls back on email_error then blocklist_reason for the reason' do
      payload = event_payload('09_notification_email_dropped.json', mailing.id).except('email_response_message')
      perform('scaleway', payload)
      expect(mailing.reload.error_msg).to eq("email_dropped: #{payload['email_error']}")

      other = Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'welcome', mailer_params: ['x'])
      perform('scaleway', with_type(payload, 'email_blocklisted').except('email_error')
                                                                .merge('blocklist_reason' => ' 550 mailbox not found ',
                                                                       'email_headers' => payload['email_headers']
                                                                         .map { |h| h.merge('value' => other.id.to_s) }))
      expect(other.reload.error_msg).to eq('email_blocklisted: 550 mailbox not found')
    end

    it 'finds the mailing whatever the case of the header key' do
      # 02 uses x-facteur-mailing-id, 05 uses X-Facteur-Mailing-Id
      replay('02_notification_email_queued.json')
      expect(mailing).to be_current_status_processed

      payload = event_payload('05_notification_email_mailbox_not_found.json', mailing.id)
      payload['email_headers'] = payload['email_headers'].map do |h|
        h['key'].casecmp?('X-Facteur-Mailing-Id') ? h.merge('key' => 'X-FACTEUR-MAILING-ID') : h
      end
      perform('scaleway', payload)

      expect(mailing.reload).to be_current_status_error
    end

    it 'computes the final state from out-of-order events' do
      replay('03_notification_email_delivered.json', '02_notification_email_queued.json')

      expect(mailing).to be_current_status_delivered
      expect(mailing.processed_at).to be < mailing.delivered_at
      expect(mailing.sorted_events.map { |e| e['type'] }).to eq(%w[email_queued email_delivered])
    end

    it 'orders events within the same second by their fraction' do
      replay('03_notification_email_delivered.json', '02_notification_email_queued.json')

      timestamps = mailing.sorted_events.map { |e| e['timestamp'] }
      expect(timestamps.map(&:floor).uniq.size).to eq(1)
      expect(timestamps).to eq(timestamps.sort)
    end

    it 'records the same event only once' do
      2.times { replay('02_notification_email_queued.json') }

      expect(mailing.events.size).to eq(1)
    end

    it 'stores the TEM email_id once in provider_message_ids' do
      replay('04_notification_email_queued.json', '07_notification_email_dropped.json',
             '05_notification_email_mailbox_not_found.json')

      expect(mailing.provider_message_ids).to eq(['b3f44b09-5c63-4ae4-85e6-26a99c5dc455'])
    end

    [
      %w[05_notification_email_mailbox_not_found.json 07_notification_email_dropped.json],
      %w[07_notification_email_dropped.json 05_notification_email_mailbox_not_found.json]
    ].each do |fixtures|
      it "keeps a single email_mailbox_not_found message when receiving #{fixtures.join(' then ')}" do
        replay(*fixtures)

        expect(mailing).to be_current_status_error
        expect(mailing.error_msg).to eq("email_mailbox_not_found: #{mailbox_not_found_reason}")
        # email_dropped is stamped before email_mailbox_not_found
        expect(mailing.error_at).to eq(Time.zone.iso8601(event_payload('07_notification_email_dropped.json')['created_at']))
      end
    end

    it 'keeps email_dropped as the message when it is the only error' do
      replay('08_notification_email_queued.json', '09_notification_email_dropped.json')

      expect(mailing).to be_current_status_error
      expect(mailing.error_msg).to eq('email_dropped: send email to facteur-test-nomx-d3ab0cfd908a.com: ' \
                                      'non-existing domain or no MX found')
    end

    describe 'ignored events' do
      before { allow(Rails.logger).to receive(:info) }

      it 'ignores an unknown mailing id' do
        expect { replay('02_notification_email_queued.json', mailing_id: 0) }.not_to raise_error

        expect(mailing.events).to be_nil
        expect(Rails.logger).to have_received(:info).with(/no mailing/)
      end

      it 'ignores a non numeric mailing id even if it starts with an existing id' do
        replay('02_notification_email_queued.json', mailing_id: "#{mailing.id}-abc")
        replay('02_notification_email_queued.json', mailing_id: "test-#{mailing.id}-d3ab0cfd908a")

        expect(mailing.events).to be_nil
      end

      it 'ignores the real payloads, whose header is not a mailing id' do
        perform('scaleway', JSON.parse(fixture_envelope('signed_raw/email_queued.json')['Message']))

        expect(Facteur::Mailing.where.not(events: nil)).to be_empty
      end

      it 'ignores an event without the header' do
        payload = event_payload('02_notification_email_queued.json')
        payload['email_headers'] = payload['email_headers'].reject { |h| h['key'].casecmp?('X-Facteur-Mailing-Id') }

        expect { perform('scaleway', payload) }.not_to raise_error
      end

      it 'ignores blocklist_created' do
        expect { perform('scaleway', event_payload('06_notification_blocklist_created.json')) }.not_to raise_error

        expect(Rails.logger).to have_received(:info).with(/blocklist_created/)
      end

      it 'ignores blank payloads and unknown providers' do
        expect { perform('scaleway', nil) }.not_to raise_error
        expect { perform('scaleway', {}) }.not_to raise_error
        expect { perform('mailjet', { 'CustomID' => mailing.id }) }.not_to raise_error

        expect(mailing.reload.events).to be_nil
      end
    end
  end

  describe 'SendGrid events' do
    let(:sendgrid_events) do
      [
        { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_288, 'event' => 'processed', 'mn_id' => mailing.id.to_s,
          'smtp-id' => '<14c5d75ce93.dfd.64b469@ismtpd-555>', 'sg_event_id' => 'sg-processed-1',
          'sg_message_id' => '14c5d75ce93.dfd.64b469.filter0001.16648.5515E0B88.0' },
        { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_290, 'event' => 'delivered', 'mn_id' => mailing.id.to_s,
          'response' => '250 OK', 'sg_event_id' => 'sg-delivered-1',
          'sg_message_id' => '14c5d75ce93.dfd.64b469.filter0001.16648.5515E0B88.0' },
        { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_300, 'event' => 'open', 'mn_id' => mailing.id.to_s,
          'useragent' => 'Mozilla/4.0', 'ip' => '255.255.255.255', 'sg_event_id' => 'sg-open-1',
          'sg_message_id' => '14c5d75ce93.dfd.64b469.filter0001.16648.5515E0B88.0' },
        { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_310, 'event' => 'bounce', 'mn_id' => mailing.id.to_s,
          'type' => 'bounce', 'status' => '5.0.0', 'reason' => '500 unknown recipient',
          'sg_event_id' => 'sg-bounce-1', 'sg_message_id' => '14c5d75ce93.dfd.64b469.filter0001.16648.5515E0B88.0' }
      ]
    end

    it 'updates the mailing as before and keeps the original SendGrid keys' do
      perform('sendgrid', sendgrid_events)

      mailing.reload
      expect(mailing.processed_at).to eq(Time.zone.at(1_794_193_288))
      expect(mailing.delivered_at).to eq(Time.zone.at(1_794_193_290))
      expect(mailing.opened_at).to eq(Time.zone.at(1_794_193_300))
      expect(mailing.error_at).to eq(Time.zone.at(1_794_193_310))
      expect(mailing.error_msg).to eq('bounce: 500 unknown recipient')
      expect(mailing).to be_current_status_error
      expect(mailing.events.size).to eq(4)
      expect(mailing.events.last).to include(
        'email' => 'jane@facteur.test', 'event' => 'bounce', 'mn_id' => mailing.id.to_s, 'status' => '5.0.0',
        'sg_event_id' => 'sg-bounce-1', 'provider' => 'sendgrid', 'provider_event_id' => 'sg-bounce-1',
        'type' => 'bounce', 'reason' => '500 unknown recipient'
      )
      expect(mailing.provider_message_ids).to eq(['14c5d75ce93.dfd.64b469.filter0001.16648.5515E0B88.0'])
    end

    it 'accepts an Integer mn_id' do
      perform('sendgrid', sendgrid_events.first.merge('mn_id' => mailing.id))

      expect(mailing.reload).to be_current_status_processed
    end

    it 'ignores a non numeric String mn_id' do
      perform('sendgrid', sendgrid_events.first.merge('mn_id' => "#{mailing.id}-abc"))

      expect(mailing.reload.events).to be_nil
    end

    it 'does not record again an event stored before normalization (sg_event_id only)' do
      legacy = sendgrid_events.first.merge('provider' => 'sendgrid')
      mailing.update!(events: [legacy])

      perform('sendgrid', sendgrid_events.first)

      expect(mailing.reload.events).to eq([legacy])
    end

    it 'records the same SendGrid event only once' do
      2.times { perform('sendgrid', sendgrid_events) }

      expect(mailing.reload.events.size).to eq(4)
    end
  end

  describe 'legacy stored events' do
    it 'still computes SendGrid events stored before normalization' do
      legacy = [
        { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_290, 'event' => 'delivered', 'mn_id' => mailing.id,
          'provider' => 'sendgrid', 'datetime' => '2026-11-09T03:01:30.000+00:00' },
        { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_288, 'event' => 'processed', 'mn_id' => mailing.id,
          'provider' => 'sendgrid' }
      ]
      mailing.update!(events: legacy)

      mailing.reload
      expect(mailing).to be_current_status_delivered
      expect(mailing.processed_at).to eq(Time.zone.at(1_794_193_288))
      expect(mailing.sorted_events.map { |e| e['event'] }).to eq(%w[processed delivered])
      expect(mailing.events).to eq(legacy)
    end
  end
end
