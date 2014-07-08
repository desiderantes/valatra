namespace Valatra {
	private MimeDatabase _mime_database = null;
	
	public MimeDatabase get_mime_database () {
		if (_mime_database == null) {
			_mime_database = new MimeDatabase ();
		}
		
		return _mime_database;
	}
	
	public class MimeDatabase {
		private HashTable<string, string> _mimes = new HashTable<string, string> (str_hash, str_equal);
		
		public MimeDatabase() {
			populate_with_defaults ();
		}
		
		public string? get_file_mime_type (string path) {
			string ext = get_path_extension (path);
			string result = null;
			
			if (ext != null)
				result = get_mime_type (ext);
			
			/* GIO: fallback
			if (result == null) {
				var file = File.new_for_path (path);
				try {
					var info = file.query_info ("standard::*", FileQueryInfoFlags.NONE);
					result = info.get_content_type ();
				} catch (Error e) {
					if (!(e is IOError.NOT_FOUND)) {
						critical ("error trying to infer mime type for file %s: %s", path, e.message);
					}
				}
			}*/
			
			return result;
		}
		
		private string? get_path_extension (string path) {
			int pos = path.last_index_of_char ('.');
			if (pos >= 0) {
				return path.substring (pos);
			}
			
			return null;
		}
		

		
		public void clear (string path) {
			_mimes.remove_all ();
		}
		
		public void populate_with_defaults () {
			_mimes.insert (".html".casefold ().collate_key (), "html");
			_mimes.insert (".htm".casefold ().collate_key (), "html");
			_mimes.insert (".js".casefold ().collate_key (), "application/javascript");
			_mimes.insert (".css".casefold ().collate_key (), "text/css");
			_mimes.insert (".txt".casefold ().collate_key (), "text/plain");
		}
		
		public void add_mime_type (string ext, string mime_type) {
			_mimes.insert (ext.casefold ().collate_key (), mime_type);
		}
		
		public string? get_mime_type (string ext) {
			return _mimes.get (ext.casefold ().collate_key ());
		}
		
		public void remove_mime_type (string ext, string mime_type) {
			_mimes.remove (ext.casefold ().collate_key ());
		}
		
		public bool contains_mime_type (string ext) {
			return _mimes.contains (ext.casefold ().collate_key ());
		}

		public void add_mime_database_file (string path) throws Error {
			try {
				string contents;
				FileUtils.get_contents (path, out contents);
				parse_mime_db (contents);
			} catch (Error e) {
				throw e;
			}
		}
		
		private void parse_mime_db (string contents) {
			int line_no = 0;
			
			foreach(string line in contents.split ("\n")) {
				if (line == "")
					continue;
				
				line_no++;
				string[] data = line.split (":");
				if (data.length == 2) {
					add_mime_type (data[0].strip (), data[1].strip ());
				} else {
					warning ("Malformed mime database line at %d", line_no);
				}
			}
		}
	}
}