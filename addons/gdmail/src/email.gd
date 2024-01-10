extends Reference
class_name Email

class Address:
	var address: String
	var personal: String
	
	func get_address_data_string() -> String:
		var ads : String

		if personal.size() > 0:
			ads = personal + " "
		else:
			ads = address.split("@")[0] + " "
			
		ads += "<" + address + ">"
		
		return ads
		
	func get_address_data_list_string() -> String:
		var ads : String

		if personal.size() > 0:
			ads = personal
		else:
			ads = address.split("@")[0]
			
		ads += ":" + address
		
		return ads

var sender_address: String = ""
var sender_personal: String = ""

#Array[Address] 
var to: Array = []
var subject: String = ""
var body: String = ""

func _init(p_to: Array = [], p_subject: String = "", p_body: String = "", p_sender_address: String = "", p_sender_personal: String = "") -> void:
	set_recipients(p_to)
	set_body(p_body)
	set_subject(p_subject)
	sender_address = p_sender_address
	sender_personal = p_sender_personal

func set_sender(p_address: String, p_personal: String = "") -> void:
	sender_address = p_address
	sender_personal = p_personal

func add_recipient(p_address: String, p_personal: String = "") -> void:
	var a : Address = Address.new()
	a.address = p_address
	a.personal = p_personal
	
	to.append(a)

func set_recipients(p_to: Array) -> void:
	to = p_to

func set_subject(p_subject: String) -> void:
	subject = p_subject

func set_body(p_body: String) -> void:
	body = p_body

func get_to_data_string() -> String:
	var ret : String
	
	for t in to:
		if !t:
			printerr("get_to_data_string(): !t")
			continue
			
		if ret.size() != 0:
			ret += ","
			
		ret += t.get_address_data_string()
			
	return ret

func get_email_data_string(email_default_sender_name : String, email_default_sender_email) -> String:
	
	var from_address : String

	if sender_address.size() > 0:
		if sender_personal.size() > 0:
			from_address = sender_personal + " "
		else:
			from_address = sender_address.split("@")[0] + " "
			
		from_address += "<" + sender_address + ">"
	else:
		if email_default_sender_name.size() > 0:
			from_address = email_default_sender_name + " "
		else:
			from_address = email_default_sender_email.split("@")[0] + " "
		
		from_address += "<" + email_default_sender_email + ">"

	return ("From: %s\nTo: <%s>\nSubject: %s\n\n%s\n" % [ from_address, get_to_data_string(), subject, body])

func _to_string() -> String:
	return ("From: %s <%s>\nTo: %s\nSubject: %s\n\n%s\n" % [sender_personal if not sender_personal.empty() else sender_address.split("@")[0], sender_address, ",".join(to), subject, body])
