extends Node

func get_test_email() -> Email:
	var mail : Email = Email.new()
	
	mail.add_recipient("recipient_email_address@email_address.email")
	#mail.add_cc("cc_email_address@email_address.email")
	mail.set_subject("SMTP Hopefullt last Test send subject")
	mail.set_body("SMTP Test Send Body\nAnd an another line.\n\n\nTest")
	
	print(mail.get_email_data_string($SMTPClientNode.email_default_sender_name, $SMTPClientNode.email_default_sender_email))
	print("=========================")
	
	return mail

#func _ready() -> void:
#	var mail : Email = get_test_email()
#
#	$SMTPClientNode.send_email(mail)

func _on_Button_pressed() -> void:
	var mail : Email = get_test_email()

	$SMTPClientNode.send_email(mail)
