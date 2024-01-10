extends Reference
class_name Email

var from_address: String = ""
var from_personal: String = ""

#Array[InternetAddress] 
var to: Array = []
var subject: String = ""
var body: String = ""

func _init(address: String, personal: String = "", to: Array = [], subject: String = "", body: String = "") -> void:
	self.address = address
	self.personal = personal
	set_recipients(to)
	set_body(body)
	set_subject(subject)

func set_sender(address: String, personal: String = "") -> void:
	self.address = address
	self.personal = personal

func add_recipient(address: String, personal: String = "") -> void:
	self.to.append([address, personal])

func set_recipients(to: Array) -> void:
	self.to = to

func set_subject(subject: String) -> void:
	self.subject = subject

func set_body(body: String) -> void:
	self.body = body

func _to_string() -> String:
	return ("From: %s <%s>\nTo: %s\nSubject: %s\n\n%s\n" % [from_personal if not from_personal.empty() else from_address.split("@")[0], from_address, ",".join(to), subject, body])
