/* TODO: this should be a tester, not main */

using Valatra;

public static int main (string[] args) {
  var app = new App ();
  var auth = new BasicHTTPAuthPlugin ("Valatra");
  app.port = 3333;

  app.use (auth);
  
  auth.authenticate.connect ((sender, args) => {
	stderr.printf ("Authentication required: %s - %s\n".printf (args.username, args.password));
	args.success = args.username == "test" && args.password == "test";
  });

  app.on(404, (req, res) => {
    res.type("text/html");
    var page = req.path;
    res.body = @"<h1>404 Not found.</h1><br><p>Requested page $page not found</p>".data;
  });

  app.get("/", (req, res) => {
    res.type("html");

    string ip = req.ip;
    res.body = @"<h1>Hello from Vala!<br>Your IP is $ip</h1>".data;
  });

  app.get("/status/:status", (req, res) => {
    res.halt(int.parse(req.params["status"]));
  });

  app.get("/blog/:user/:post_id", (req, res) => {
    var user = req.params["user"];
    var post = req.params["post_id"];

    res.body = @"Hello $user, here is post #$post.".data;
  });

  app.get("/login", (req, res) => {
	var user = req.headers["Authorization"];
    res.body = @"Hello '$user'.".data;
  }).before (auth);

  app.get("/cookie", (req, res) => {
    var cookie = req.session["mycookie"];

    res.type("text/plain");

    // cookie times out in 5 seconds
    if(cookie == null) {

      var timeOut = new Cookie("mycookie", "abc");
      timeOut.max_age = 5;
      res.session["mycookie"] = timeOut;
      res.body = "Cookie was null, setting it to \"abc\"".data;

    } else {
      res.body = @"Cookie was not null, it was $cookie".data;
    }

  });

  app.get("/cache", (req, res) => {
    var rnd = new Rand();
    var n = rnd.next_int();
    var body = @"This page will be cached. To prove it, here's a random number $n";

    var ent = new CacheEntry(body);
    // need to reference app indirectly for some reason...
    req.app.cache.set("/cache", ent);

    res.headers["Etag"] = ent.etag;
    res.body = body.data;
  });

  app.get("/cache/clear", (req, res) => {
    req.app.cache.invalidate("/cache");

    res.body = "Cleared cache".data;
  });

  // expects POST /post with body name=Some+Name&age=Some+age
  app.post("/post", (req, res) => {
    var body = req.body;
    var name = req.params["name"];
    var age  = req.params["age"];

    res.body = @"Oh, now I get it, $name is $age years old. Full POST data =>$body".data;
  });

  app.start();

  return 0;
}

