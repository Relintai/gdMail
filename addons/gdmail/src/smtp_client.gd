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

export(String) var host : String = ""
export(int) var port : int = 465

# TLS_METHOD_NONE: 
# No encryption.
# Username / Password will be sent without encryption.
# Not recommended if you don't know what you are doing.

# TLS_METHOD_STARTTLS
# Connect, then use the STARTTLS command, and upgarde to using SSL

# TLS_METHOD_SMTPS
# Connect, and immediately just set up SSL

enum TLSMethod {
	TLS_METHOD_NONE = 0, # Usual port 587
	TLS_METHOD_STARTTLS, # Usual port 587
	TLS_METHOD_SMTPS, # Usual port 465
}

export(int, "NONE,STARTTLS,SMTPS") var tls_method : int = TLSMethod.TLS_METHOD_SMTPS

# Authentication
enum ServerAuthMethod {
	SERVER_AUTH_PLAIN,
	SERVER_AUTH_LOGIN
}

export(String) var server_auth_username : String
export(String) var server_auth_password : String
#Method
export(int, "Plain,Login") var server_auth_method : int = ServerAuthMethod.SERVER_AUTH_LOGIN

export(String) var email_default_sender_email : String
export(String) var email_default_sender_name : String

export(bool) var use_threading : bool = true
export(int) var thread_sleep_usec : int = 10000 # 10 msec

# Networking
var _tls_client : StreamPeerSSL = StreamPeerSSL.new()
var _tcp_client : StreamPeerTCP = StreamPeerTCP.new()

#SessionStatus
var _current_session_status : int = SessionStatus.NONE
var _current_session_email : Email = null
var _current_to_index : int = 0
var _current_cc_index : int = 0

var _current_tls_started : bool = false
var _current_tls_established : bool = false

# Threading
var _worker_thread_running : bool = true
var _worker_thread : Thread
var _worker_semaphore : Semaphore = Semaphore.new()
var _mail_queue_mutex : Mutex = Mutex.new()

var _mail_queue : Array

func send_email(p_email: Email) -> void:
	if !is_inside_tree():
		PLogger.log_error("send_email !is_inside_tree()")
		return
		
	if use_threading:
		_mail_queue_mutex.lock()
		_mail_queue.push_back(p_email)
		_mail_queue_mutex.unlock()
		
		_worker_semaphore.post()
	else:
		_send_email(p_email)
	
func _send_email(p_email: Email) -> void:
	_current_session_email = p_email
	
	if !_current_session_email:
		return
	
	#Error
	var err: int = _tcp_client.connect_to_host(host, port)
	if err != OK:
		printerr("Could not connect! " + str(err))
		var error_body: Dictionary = { "message": "Error connecting to host.", "code": err }
		emit_signal(@"error", error_body)
		emit_signal(@"result", { "success": false, "error": error_body })
		if !use_threading:
			set_process(false)
		
	if tls_method == TLSMethod.TLS_METHOD_SMTPS:
		#Error
		err = _tls_client.connect_to_stream(_tcp_client, false, host)
		#var err: int = _tls_client.connect_to_stream(_tcp_client, host, tls_options)
		if err != OK:
			_current_session_status = SessionStatus.SERVER_ERROR
			var error_body: Dictionary = { "message": "Error connecting to TLS Stream.", "code": err }
			emit_signal(@"error", error_body)
			emit_signal(@"result", { "success": false, "error": error_body })
			if !use_threading:
				set_process(false)
			return
			
		_current_tls_started = true
		_current_tls_established = true
	
	_current_session_status = SessionStatus.HELO
	
	if !use_threading:
		set_process(true)

func poll_client() -> int: #Error
	if _current_tls_started or _current_tls_established:
		_tls_client.poll()
		return 0
	else:
		#return _tcp_client.poll()
		return OK

func client_get_status() -> bool:
	if _current_tls_started:
		return _tls_client.get_status() == StreamPeerSSL.STATUS_CONNECTED
	
	return _tcp_client.get_status() == StreamPeerTCP.STATUS_CONNECTED

func client_get_available_bytes() -> int:
	if _current_tls_started:
		return _tls_client.get_available_bytes()
	
	return _tcp_client.get_available_bytes()

func client_get_string(bytes : int) -> String:
	if _current_tls_started:
		return _tls_client.get_string(bytes)
	
	return _tcp_client.get_string(bytes)


func start_auth() -> bool:
	if server_auth_method == ServerAuthMethod.SERVER_AUTH_PLAIN:
		_current_session_status = SessionStatus.AUTHENTICATED
		return true
	
	if not write_command("AUTH LOGIN"):
		return false
	
	_current_session_status = SessionStatus.AUTH_LOGIN
	return true

func start_hello() -> bool:
	#_current_session_status = SessionStatus.HELO
	if not write_command("HELO " + client_id):
		return false
		
	_current_session_status = SessionStatus.HELO_ACK
	return true

func client_put_data(data : PoolByteArray) -> int:
	if _current_tls_established:
		return _tls_client.put_data(data)
	
	return _tcp_client.put_data(data)

func write_command(command: String) -> bool:
	#Error
	print("COMMAND: " + command)
	var err: int = client_put_data((command + "\n").to_utf8())
	if err != OK:
		_current_session_status = SessionStatus.COMMAND_NOT_SENT
		var error_body: Dictionary = { "message": "Session error on command: %s" % command, "code": err }
		emit_signal(@"error", error_body)
		emit_signal(@"result", { "success": false, "error": error_body })
		
	return (err == OK)

func write_data(data: String) -> int: #Error
	return client_put_data((data + "\r\n.\r\n").to_utf8())

func close_connection() -> void:
	_current_session_status = SessionStatus.NONE
	_tls_client.disconnect_from_stream()
	_tcp_client.disconnect_from_host()
	_current_session_email = null
	_current_to_index = 0
	_current_tls_started = false
	_current_tls_established = false
	if !use_threading:
		set_process(false)

func encode_username() -> String:
	return Marshalls.utf8_to_base64(server_auth_username)

func encode_password() -> String:
	return Marshalls.utf8_to_base64(server_auth_password)

func _process_email() -> void:
	if _current_session_status == SessionStatus.SERVER_ERROR:
		close_connection()
	
	if poll_client() == OK:
		var connected: bool = client_get_status()
		
		if connected:
			var bytes: int = client_get_available_bytes()
			
			if bytes > 0:
				var msg: String = client_get_string(bytes)
				print("RECEIVED: " + msg)
				var code: String = msg.left(3)
				match code:
					"220":
						match _current_session_status:
							SessionStatus.HELO:
								start_hello()
							
							SessionStatus.STARTTLS:
								#Error
								var err: int = _tls_client.connect_to_stream(_tcp_client, false, host)
								#var err: int = _tls_client.connect_to_stream(_tcp_client, host, tls_options)
								if err != OK:
									_current_session_status = SessionStatus.SERVER_ERROR
									var error_body: Dictionary = { "message": "Error connecting to TLS Stream.", "code": err }
									emit_signal("@error", error_body)
									emit_signal(@"result", { "success": false, "error": error_body })
									return
									
								_current_tls_started = true
								_current_tls_established = true
							
								# We need to do HELO + EHLO again
								_current_session_status = SessionStatus.HELO
								start_hello()

					"250":
						match _current_session_status:
							SessionStatus.HELO_ACK:
								if not write_command("EHLO " + client_id):
									return
											
								_current_session_status = SessionStatus.EHLO_ACK
									
							SessionStatus.EHLO_ACK:
								if tls_method == TLSMethod.TLS_METHOD_STARTTLS:
									if _current_tls_started:
										# second round of HELO + EHLO done
										if not start_auth():
											return
									else:
										if not write_command("STARTTLS"):
											return
											
										_current_session_status = SessionStatus.STARTTLS
								else:
									if not start_auth():
										return
							
							SessionStatus.MAIL_FROM:
								if (_current_to_index < _current_session_email.to.size()):
									if not write_command("RCPT TO: <%s>" % _current_session_email.to[_current_to_index].address):
										return
									_current_to_index += 1
										
								if (_current_cc_index < _current_session_email.cc.size()):
									if not write_command("RCPT TO: <%s>" % _current_session_email.cc[_current_cc_index].address):
										return
									_current_cc_index += 1
									
								_current_session_status = SessionStatus.RCPT_TO

							SessionStatus.RCPT_TO:
								if (_current_to_index < _current_session_email.to.size()):
									_current_session_status = SessionStatus.MAIL_FROM
									return
									
								if (_current_cc_index < _current_session_email.cc.size()):
									_current_session_status = SessionStatus.MAIL_FROM
									return
								
								if not write_command("DATA"):
									return
								_current_session_status = SessionStatus.DATA
							
							SessionStatus.DATA_ACK:
								if not write_command("QUIT"):
									return
								_current_session_status = SessionStatus.QUIT
					"221":
						match _current_session_status:
							SessionStatus.QUIT:
								close_connection()
								emit_signal(@"email_sent")
								emit_signal(@"result", { "success": true })
					"235": # Authentication Succeeded
						match _current_session_status:
							SessionStatus.PASSWORD:
								_current_session_status = SessionStatus.AUTHENTICATED
					"334":
						match _current_session_status:
							SessionStatus.AUTH_LOGIN:
								if msg.begins_with("334 VXNlcm5hbWU6"):
									if not write_command(encode_username()):
										return
									_current_session_status = SessionStatus.USERNAME
							
							SessionStatus.USERNAME:
								if msg.begins_with("334 UGFzc3dvcmQ6"):
									if not write_command(encode_password()):
										return
									_current_session_status = SessionStatus.PASSWORD
					"354":
						match _current_session_status:
							SessionStatus.DATA:
								#TODO To has bad szntax
								#TODO ADD cc
								if not (write_data(_current_session_email.get_email_data_string(email_default_sender_name, email_default_sender_email)) == OK):
									_current_session_status = SessionStatus.SERVER_ERROR
									return
								_current_session_status = SessionStatus.DATA_ACK
					_:
						printerr(msg)

		if _current_session_email != null and (_current_session_status == SessionStatus.AUTHENTICATED):
			_current_session_status = SessionStatus.MAIL_FROM
			
			var fn : String
			
			if _current_session_email.sender_address.size() > 0:
				fn = "<" + _current_session_email.sender_address + ">"
			else:
				fn = "<" + email_default_sender_email + ">"
				
			if not write_command("MAIL FROM: " + fn):
				return
		
		else:
			return
	else:
		printerr("Couldn't poll!")

func _worker_thread_func(user_data):
	while _worker_thread_running:
		var _mail : Email = null
		
		print("Thread loop")
		
		_mail_queue_mutex.lock()
		_mail = _mail_queue.pop_front()
		_mail_queue_mutex.unlock()
		
		if _mail:
			_send_email(_mail)
			
		while _current_session_email:
			OS.delay_usec(thread_sleep_usec)
			
			# Early return if we want to quit
			if !_worker_thread_running:
				close_connection()
				return
			
			_process_email()
			
		if !_worker_thread_running:
			return
		
		if _mail_queue.size() == 0:
			_worker_semaphore.wait()

func _process(delta: float) -> void:
	if use_threading:
		set_process(false)
		return
		
	_process_email()

func _ready() -> void:
	set_process(false)
	
	if use_threading:
		_worker_thread_running = true
		_worker_thread = Thread.new()
		_worker_thread.start(self, @"_worker_thread_func", 1)
		
func _exit_tree() -> void:
	if _worker_thread:
		_worker_thread_running = false
		_worker_semaphore.post()
		_worker_thread.wait_to_finish()
		_worker_thread = null
