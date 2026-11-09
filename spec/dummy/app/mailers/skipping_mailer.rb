# frozen_string_literal: true

class SkippingMailer < ApplicationMailer
  def self.should_skip_facteur_mailing?(_mailing)
    true
  end

  def welcome(to)
    mail(to: to, subject: 'Skipped', body: 'Never sent', content_type: 'text/plain')
  end
end
