extends Node
class_name SMTPClientNode

#error: Dictionary
signal error(error)
signal email_sent()
#content: Dictionary
signal result(content)

enum SessionStatus {
	NONE,
	SERVER_ERROR,
	COMMAND_NOT_SENT,
	COMMAND_REFUSED,
	HELO,
	HELO_ACK,
	EHLO,
	EHLO_ACK,
	MAIL_FROM,
	RCPT_TO,
	DATA,
	DATA_ACK,
	QUIT,
	STARTTLS,
	STARTTLS_ACK,
	AUTH_LOGIN,
	USERNAME,
	PASSWORD,
	AUTHENTICATED
}

export(String) var client_id: String = "smtp.pandemoniumengine.org"

export(String) var host: String = ""
export(int) var port: int = 587

# TLS_METHOD_NONE: 
# No encryption.
# Username / Password will be sent without encryption.
# Not recommended if you don't know what you are doing.

# TLS_METHOD_STARTTLS
# Connect, then use the STARTTLS command, and upgarde to using SSL

# TLS_METHOD_SMTPS
# Connect, and immediately just set up SSL

enum TLSMethod {
	TLS_METHOD_NONE = 0, # Usual port 465
	TLS_METHOD_STARTTLS, # Usual port 465
	TLS_METHOD_SMTPS, # Usual port 587
}

export(int, "NONE,STARTTLS,SMTPS") var tls_method : int = TLSMethod.TLS_METHOD_SMTPS
var tls_started : bool = false
var tls_established : bool = false

# Authentication
enum ServerAuthMethod {
	SERVER_AUTH_PLAIN,
	SERVER_AUTH_LOGIN
}

export(String) var server_auth_username: String
export(String) var server_auth_password: String
#Method
export(int, "Plain,Login") var server_auth_method: int = ServerAuthMethod.SERVER_AUTH_LOGIN

# Networking
var tls_client: StreamPeerSSL = StreamPeerSSL.new()
var tcp_client: StreamPeerTCP = StreamPeerTCP.new()

#SessionStatus
var session_status: int = SessionStatus.NONE

export(String) var email_default_sender_email : String
export(String) var email_default_sender_name : String

var email: Email = null
var to_index: int = 0

func send_email(email: Email) -> void:
	self.email = email
	
	#Error
	var err: int = tcp_client.connect_to_host(host, port)
	if err != OK:
		printerr("Could not connect!")
		var error_body: Dictionary = { "message": "Error connecting to host.", "code": err }
		emit_signal(@"error", error_body)
		emit_signal(@"result", { "success": false, "error": error_body })
		set_process(false)
		
	if tls_method == TLSMethod.TLS_METHOD_SMTPS:
		#Error
		err = tls_client.connect_to_stream(tcp_client, false, host)
		#var err: int = tls_client.connect_to_stream(tcp_client, host, tls_options)
		if err != OK:
			session_status = SessionStatus.SERVER_ERROR
			var error_body: Dictionary = { "message": "Error connecting to TLS Stream.", "code": err }
			emit_signal(@"error", error_body)
			emit_signal(@"result", { "success": false, "error": error_body })
			set_process(false)
			return
			
		tls_started = true
		tls_established = true
	
	session_status = SessionStatus.HELO

	set_process(true)

func poll_client() -> int: #Error
	if tls_started or tls_established:
		tls_client.poll()
		return 0
	else:
		return tcp_client.poll()

func _process(delta: float) -> void:
	if session_status == SessionStatus.SERVER_ERROR:
		close_connection()
	
	if poll_client() == OK:
		var connected: bool = (tcp_client.get_status() == StreamPeerTCP.STATUS_CONNECTED if not tls_started else tls_client.get_status() == StreamPeerSSL.STATUS_CONNECTED)
		
		if connected:
			var bytes: int = (tcp_client if not tls_established else tls_client).get_available_bytes()
			
			if bytes > 0:
				var msg: String = (tcp_client if not tls_established else tls_client).get_string(bytes)
				print("RECEIVED: " + msg)
				var code: String = msg.left(3)
				match code:
					"220":
						match session_status:
							SessionStatus.HELO:
								start_hello()
							
							SessionStatus.STARTTLS:
								#Error
								var err: int = tls_client.connect_to_stream(tcp_client, false, host)
								#var err: int = tls_client.connect_to_stream(tcp_client, host, tls_options)
								if err != OK:
									session_status = SessionStatus.SERVER_ERROR
									var error_body: Dictionary = { "message": "Error connecting to TLS Stream.", "code": err }
									emit_signal("@error", error_body)
									emit_signal(@"result", { "success": false, "error": error_body })
									return
									
								tls_started = true
								
								# We need to do HELO + EHLO again
								#session_status = SessionStatus.HELO
								start_hello()
					"250":
						match session_status:
							SessionStatus.HELO_ACK:
								if not write_command("EHLO " + client_id):
									return
											
								session_status = SessionStatus.EHLO_ACK
									
							SessionStatus.EHLO_ACK:
								if tls_method == TLSMethod.TLS_METHOD_STARTTLS:
									if tls_started:
										# second round of HELO + EHLO done
										if not start_auth():
											return
									else:
										if not write_command("STARTTLS"):
											return
											
										session_status = SessionStatus.STARTTLS
								else:
									if not start_auth():
										return
							
							SessionStatus.MAIL_FROM:
								#TODO
								#Response:
								#250 2.1.5 Ok
								#500 5.5.2 Error: bad syntax
								if not write_command("RCPT TO: <%s>" % email.to[to_index].address + "\n"):
									return
									
								session_status = SessionStatus.RCPT_TO
								to_index += 1
							
							SessionStatus.RCPT_TO:
								if (to_index < email.to.size()):
									session_status = SessionStatus.MAIL_FROM
									return
								
								if not write_command("DATA"):
									return
								session_status = SessionStatus.DATA
							
							SessionStatus.DATA_ACK:
								if not write_command("QUIT"):
									return
								session_status = SessionStatus.QUIT
					"221":
						match session_status:
							SessionStatus.QUIT:
								close_connection()
								emit_signal(@"email_sent")
								emit_signal(@"result", { "success": true })
					"235": # Authentication Succeeded
						match session_status:
							SessionStatus.PASSWORD:
								session_status = SessionStatus.AUTHENTICATED
					"334":
						match session_status:
							SessionStatus.AUTH_LOGIN:
								if msg.begins_with("334 VXNlcm5hbWU6"):
									if not write_command(encode_username()):
										return
									session_status = SessionStatus.USERNAME
							
							SessionStatus.USERNAME:
								if msg.begins_with("334 UGFzc3dvcmQ6"):
									if not write_command(encode_password()):
										return
									session_status = SessionStatus.PASSWORD
					"354":
						match session_status:
							SessionStatus.DATA:
								#TODO To has bad szntax
								#TODO ADD cc
								if not (write_data(email.get_email_data_string(email_default_sender_name, email_default_sender_email)) == OK):
									session_status = SessionStatus.SERVER_ERROR
									return
								session_status = SessionStatus.DATA_ACK
					_:
						printerr(msg)
						
		
		if email != null and (session_status == SessionStatus.AUTHENTICATED):
			session_status = SessionStatus.MAIL_FROM
			
			var fn : String
			
			if email.sender_address.size() > 0:
				fn = "<" + email.sender_address + ">"
			else:
				fn = "<" + email_default_sender_email + ">"
				
			if not write_command("MAIL FROM: " + fn):
				return
		
		else:
			return
	else:
		printerr("Couldn't poll!")

func start_auth() -> bool:
	if server_auth_method == ServerAuthMethod.SERVER_AUTH_PLAIN:
		session_status = SessionStatus.AUTHENTICATED
		return true
	
	if not write_command("AUTH LOGIN"):
		return false
	
	session_status = SessionStatus.AUTH_LOGIN
	return true

func start_hello() -> bool:
	#session_status = SessionStatus.HELO
	if not write_command("HELO " + client_id):
		return false
		
	session_status = SessionStatus.HELO_ACK
	return true

func write_command(command: String) -> bool:
	#Error
	print("COMMAND: " + command)
	var err: int = (tls_client if tls_established else tcp_client).put_data((command + "\n").to_utf8())
	if err != OK:
		session_status = SessionStatus.COMMAND_NOT_SENT
		var error_body: Dictionary = { "message": "Session error on command: %s" % command, "code": err }
		emit_signal(@"error", error_body)
		emit_signal(@"result", { "success": false, "error": error_body })
		
	return (err == OK)

func write_data(data: String) -> int: #Error
	return (tls_client if tls_established else tcp_client).put_data((data + "\r\n.\r\n").to_utf8())

func close_connection() -> void:
	session_status = SessionStatus.NONE
	tls_client.disconnect_from_stream()
	tcp_client.disconnect_from_host()
	email = null
	to_index = 0
	tls_started = false
	tls_established = false
	set_process(false)

func encode_username() -> String:
	return Marshalls.utf8_to_base64(server_auth_username)

func encode_password() -> String:
	return Marshalls.utf8_to_base64(server_auth_password)

func _ready() -> void:
	set_process(false)
