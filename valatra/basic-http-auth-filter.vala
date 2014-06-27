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

	public class BasicHTTPAuthFilter : HTTPFilterModule {
		private StatusWrapper? original_status_wrapper_;
		
		public string realm { get; set; }
		
		public signal void authenticate (BasicHTTPAuthFilter sender, BasicHTTPAuthArgs args);
		
		public BasicHTTPAuthFilter (App app, string realm)
		{
			base (app);		
			this.realm = realm;
			
			original_status_wrapper_ = app.get_status_handler (401);
			
			app.on(401, (req, res) => {
				if (original_status_wrapper_ != null) {
					original_status_wrapper_.func (req, res);
				}
				
				// basic HTTP authentication
				res.headers["WWW-Authenticate"] = "Basic realm=\"%s\"".printf (this.realm);
				if ((res.body ?? "") == "") {
					res.body = @"Authentication failed (BasicHttpAuth)";
				}
			});
		}
		
		public override void filter (HTTPRequest req, HTTPResponse res) throws HTTPStatus {
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
