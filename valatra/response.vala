namespace Valatra {
  public class HTTPResponse : GLib.Object {
    private int status_;
    private string status_msg_;
    private uint8[] body_;

    public HashTable<string, string> headers;
    public HashTable<string, Cookie> session;

    public int status {
      get { return status_; }
      set { status_ = value;}
    }

    public string status_msg {
      get { return status_msg_; }
      set { status_msg_ = value; }
    }

    public uint8[] body {
      get { return body_; }
      set { body_ = value;}
    }
	
    public HTTPResponse() {
      status_ = 200;
      status_msg_ = "OK";
      body_ = null;

      headers = new HashTable<string, string>(str_hash, str_equal);
      session = new HashTable<string, Cookie>(str_hash, str_equal);

      default_headers();
    }

    public HTTPResponse.with_status(int status, string msg) {
      status_ = status;
      status_msg_ = msg;
      body_ = null;
      headers = new HashTable<string, string>(str_hash, str_equal);
      session = new HashTable<string, Cookie>(str_hash, str_equal);

      default_headers();
    }

    private void default_headers() {
      headers["Connection"] = "close";
      headers["Content-type"] = "text/plain";
      headers["X-Powered-By"] = "valatra";
    }

    public void type(string t) {
      if(t == "html") {
        headers["Content-type"] = "text/html";
      } else if(t == "plain") {
        headers["Content-type"] = "text/plain";
      } else {
        // TODO: add more types
        headers["Content-type"] = t;
      }
    }

    public void halt(int stat) throws HTTPStatus {
      throw new HTTPStatus.STATUS(stat.to_string());
    }

    public void create(DataOutputStream dos) {
      try {
        dos.put_string(@"HTTP/1.1 $status_ $status_msg_\r\n");

        if(body_ != null && body_.length != 0) {
          headers["Content-length"] = body_.length.to_string();
        } else {
          headers.remove ("Content-length");
          headers.remove ("Content-type");
        }

     	headers.foreach ((key, val) => {
			dos.put_string("%s: %s\r\n".printf (key, val));
		});

		session.foreach ((key, val) => {
			var v = val.create();
			dos.put_string("Set-Cookie: %s\r\n".printf (v));
		});
		
		dos.put_string(@"\r\n");
		if (body_ != null && body_.length > 0) {
			size_t written;
			dos.write_all (body_, out written);
		}
      } catch(IOError e) {
        critical ("create: %s", e.message);
      }
    }
  }
}

