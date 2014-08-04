namespace Valatra {
	public class BasicHTTPAuthArgs {
		public string username { get; set; }
		public string? password { get; set; }
		
		public bool success { get; set; }
		
		public BasicHTTPAuthArgs (string username, string? password) {
			this.username = username;
			this.password = password;
			this.success = false;
		}
	}

	public class BasicHTTPAuthPlugin : HTTPPlugin {
		private StatusWrapper? original_status_wrapper_;
		
		public string realm { get; set; }
		
		public signal void authenticate (BasicHTTPAuthPlugin sender, BasicHTTPAuthArgs args);
		
		public BasicHTTPAuthPlugin (string realm)
		{
			this.realm = realm;
		}
		
		public override void on_install (Valatra.App app) {
			original_status_wrapper_ = app.get_status_handler (401);
			
			app.on(401, (req, res) => {
				if (original_status_wrapper_ != null) {
					original_status_wrapper_.func (req, res);
				}
				
				// basic HTTP authentication
				res.headers["WWW-Authenticate"] = "Basic realm=\"%s\"".printf (this.realm);
				if (res.body == null || res.body.length == 0) {
					res.body = @"Authentication failed (BasicHttpAuth)".data;
				}
			});
		}
		
		public override void process_request (HTTPRequest req, HTTPResponse res) throws HTTPStatus {
			var header = req.headers["Authorization"] ?? "";
			
			if (header == "")
				res.halt (401);
				
			string[] auth = header.split (" ");
			
			if (auth[0] == "Basic") {
				var credentials = ((string) Base64.decode (auth[1])).split(":");
				var args = new BasicHTTPAuthArgs (credentials[0], credentials[1]);
				this.authenticate (this, args);
				if (!args.success) {
					res.halt (401);
				}
			}
		}
	}
}
