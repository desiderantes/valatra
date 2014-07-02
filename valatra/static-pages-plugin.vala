namespace Valatra {
	public class StaticPagesPlugin : Plugin {
		private Timer _timer = new Timer ();
		
		public string virtual_path { get; construct set; }
		public string root_path { get; construct set; }
		
		public StaticPagesPlugin (string virtual_path, string root_path) {
			this.virtual_path = virtual_path;
			this.root_path = root_path;
		}
	
		public override void on_install (Valatra.App app) {
			app.get ("%s.*".printf (Path.build_path ("/", virtual_path)), this.process_request);
		}
		
		protected virtual void process_request (HTTPRequest req, HTTPResponse res) throws HTTPStatus {
			res.type("html");

			string req_path = req.path;
			// serve static pages
			if (req_path == null || req_path == "" || req_path == "/")
				req_path = "index.html";
			
			string path = Path.build_path (Path.DIR_SEPARATOR_S, this.root_path, req_path.replace ("/", Path.DIR_SEPARATOR_S));
			try {
				string page;
				ulong usec = 0;
				
				_timer.start ();
				FileUtils.get_contents (path, out page);
				res.body = page;
				
				debug ("serving page: %s in %gs (%luus)\n", path, _timer.elapsed (out usec), usec);
			} catch (FileError e) {
				if (e is FileError.NOENT) {
					debug ("page %s not found\n", path);
					throw new HTTPStatus.STATUS ("404");
				} else {
					critical ("error reading file %s: %s\n", path, e.message);
					throw new HTTPStatus.STATUS ("504");
				}
			}
		}
	}
}