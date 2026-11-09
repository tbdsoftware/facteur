# frozen_string_literal: true

class TestMailer < ApplicationMailer
  def welcome(to, subject = 'Welcome')
    mail(to: to, subject: subject, body: "Hello #{to}", content_type: 'text/plain')
  end

  def notification
    mail(to: params[:to], subject: params[:subject] || 'Notification', body: 'You have a notification',
         content_type: 'text/plain')
  end
end
