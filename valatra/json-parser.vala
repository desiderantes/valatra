namespace Valatra.Json {
	public errordomain ParseError {
		SYNTAX,
		EOF,
		UNKNOWN_OBJECT_TYPE
	}

	private abstract class JsonToken : Object {
		public int start;
		public int end;
		
		public JsonToken? owner = null;
		
		public virtual string to_string () {
			Type? type = this.get_type ();
			assert (type != null);
				
			var type_name = type.name ();
			return "%s (%d-%d)".printf (type_name, start, end);
		}
		
		public abstract string to_json (string sep = " ");
	}
	
	private abstract class ValueToken: JsonToken {
	}
	
	private class StringToken: ValueToken {
		public string value;
		
		public StringToken () {
		}
		
		public StringToken.with_value (string value) {
			this.value = value;
		}
		
		public override string to_string () {
			return "%s: %s".printf (base.to_string (), value);
		}
		
		public override string to_json (string sep = " ") {
			return "\"%s\"".printf (value);
		}
	}
	
	private class BooleanToken: ValueToken {
		public bool value;
		
		public BooleanToken () {
		}
		
		public BooleanToken.with_value (bool value) {
			this.value = value;
		}
		
		public override string to_string () {
			return "%s: %s".printf (base.to_string (), value ? "true" : "false");
		}
		
		public override string to_json (string sep = " ") {
			return "%s".printf (value ? "true" : "false");
		}
	}
	
	private class NumberToken: ValueToken {
		public double value;
		
		public NumberToken () {
		}
		
		public NumberToken.with_value (double value) {
			this.value = value;
		}
		
		public override string to_string () {
			return "%s: %g".printf (base.to_string (), value);
		}
		
		public override string to_json (string sep = " ") {
			return "%g".printf (value);
		}
	}
	
	private class ObjectToken : JsonToken {
		public List<TupleToken> values = new List<TupleToken> ();
		public Object? instance = null;
		
		public override string to_json (string sep = " ") {
			var sb = new StringBuilder ();

			sb.append ("{");
			sb.append (sep);
			bool first = true;
			foreach (var value in values) {
				if (!first) {
					sb.append (",");
					sb.append (sep);
				} else {
					first = false;
				}
				sb.append (value.to_json ());
			}
			sb.append (sep);
			sb.append ("}");
			sb.append (sep);
			return sb.str;
		}
	}

	private class ArrayToken : JsonToken {
		public List<JsonToken> values = new List<JsonToken> ();
		
		public override string to_json (string sep = " ") {
			var sb = new StringBuilder ();

			sb.append ("[");
			sb.append (sep);
			bool first = true;
			foreach (var value in values) {
				if (!first) {
					sb.append (",");
					sb.append (sep);
				} else {
					first = false;
				}
				sb.append (value.to_json ());
			}
			sb.append ("]");
			sb.append (sep);
			return sb.str;
		}
	}

	private class TupleToken : JsonToken {
		private JsonToken? _value = null;
		
		public StringToken? name = null;
		
		public JsonToken? value {
			get {
				return _value;
			}
			set {
				_value = value;
				if (this.owner is ObjectToken) {
					var obj = (ObjectToken)this.owner;
					if (obj.instance != null) {
						if (_value is NumberToken) {
							var v = ((NumberToken)value).value;
							if (v == Math.round (v)) {
								obj.instance.set (name.value, (int) ((NumberToken)value).value);
							} else {
								obj.instance.set (name.value, (double) ((NumberToken)value).value);
							}
							
						} else if (_value is StringToken) {
							obj.instance.set (name.value, (string) ((StringToken)value).value);
						} else if (_value is ObjectToken) {
							obj.instance.set (name.value, (Object) ((ObjectToken)value).instance);
						} else if (_value is BooleanToken) {
							obj.instance.set (name.value, (bool) ((BooleanToken)value).value);
						} else if (_value is ArrayToken) {
							//critical ("Unsupported value type: %s (%p)", _value.get_type ().name (), _value);
						} else {
							critical ("Unsupported value type: %s (%p)", _value.get_type ().name (), _value);
						}
					}
				}
			}
		}
		
		public override string to_string () {
			return "%s: [%s] = [%s]".printf (base.to_string (), name == null ? "(null)" : name.to_string (), value == null ? "(null)" : value.to_string ());
		}
		
		public override string to_json (string sep = " ") {
			return "%s: %s".printf (name.to_json (), value == null ? "null" : value.to_json ());
		}
	}
	
	public delegate Object? ParserClassFactory (Type type, string? prop_name);
	public delegate Object? ParserArrayItemFactory (Object? owner, string? prop_name, uint index);

	public static Object? standard_class_factory (Type type, string? prop_name) {
		var instance = Object.@new (type);
		return instance;
	}
	
	public static Object? standard_array_item_factory (Object? owner, string? prop_name, uint index) {
		Object? instance = null;
		
		if (owner != null) {
			if (prop_name != null) {
				unowned Array<Object> a = null;
				
				owner.get (prop_name, &a);
				if (a != null) {
					instance = a.index (index);
				} else {
					critical ("standard_array_item_factory: array instance is null.");
				}
			} else {
				critical ("standard_array_item_factory: prop_name (%s) cannot be null and should be a valid property name of object %s (%p).", prop_name, owner.get_type ().name (), owner);
			}
		} else {
			critical ("standard_array_item_factory: owner cannot be null.");
		}
		
		return instance;
	}
	
	public T? parse<T> (string? data, ParserClassFactory class_factory = standard_class_factory, ParserArrayItemFactory array_item_factory = standard_array_item_factory) throws Error {
		JsonToken current = null;
		int i = 0;
		
		if (data == null)
			return null;
		
		while (i < data.length) {
			try {
				skip_spaces (data, ref i);
				
				if (i < data.length) {
					char ch = data[i];
					
					if (ch == '{') {
						var obj = new ObjectToken ();
						string prop_name = null;
						Type? type = null;
						
						if (current == null) {
							type = typeof (T);
						}
						if (current is TupleToken) {
							var t = (TupleToken)current;
							if (t.name != null)
								prop_name = t.name.value;
								
							if (t.owner is Object && prop_name != null) {
								var prop = ((ObjectClass) ((Object)((ObjectToken)current.owner).instance).get_type ().class_ref ()).find_property (prop_name);
								if (prop != null)
									type = prop.value_type;
							}
						}
						
						
						if (type != null) {
							obj.instance = class_factory (type, prop_name);
						} else {
							if (current is ArrayToken) {
								var a = (ArrayToken)current;
								string array_owner_prop_name = null;
								Object? array_owner_object = null;
								
								if (a.owner is TupleToken) {
									array_owner_prop_name = ((TupleToken)a.owner).name.value;
									array_owner_object = ((ObjectToken)((TupleToken)a.owner).owner).instance;
								} else if (a.owner is ObjectToken) {
									array_owner_object = ((ObjectToken)a.owner).instance;
								}
								
								obj.instance = array_item_factory (array_owner_object, array_owner_prop_name, (uint)a.values.length ());
							} else {
								throw new ParseError.UNKNOWN_OBJECT_TYPE ("Unknown object type for property name: '%s'".printf (prop_name == null ? "(null)" : prop_name));
							}
						}
						obj.start = i;
						obj.owner = current;
						current = obj;
						i++;
					} else if (ch == ':') {
						if (!(current is StringToken)) {
							throw new ParseError.SYNTAX ("syntax error parsing tuple, unexpected ':'");
						}
						if (!(current.owner is ObjectToken)) {
							throw new ParseError.SYNTAX ("syntax error parsing tuple, owner is not an Object: %s (%s)".printf (current.owner == null ? "(null)" : current.owner.get_type ().name (), current.to_string ()));
						}
						var token = new TupleToken ();
						token.start = current.start;
						token.name = (StringToken)current;
						token.owner = current.owner;
						current.owner = token;
						current = token;
						i++;
					} else if (ch == '}') {
						current.end = i;
						var token = current;
						current = current.owner;
						current.end = i;
						i++;
						if (current is TupleToken) {
							var t = (TupleToken) current;
							t.value = token;
							current = current.owner;
						} else if (current is ArrayToken) {
							var a = (ArrayToken) current.owner;
							a.values.append (token);
						} else {
							throw new ParseError.SYNTAX ("syntax error %s".printf (current == null ? "(null)" : current.to_string ()), i);
						}
					} else if (ch == '[') {
						var token = new ArrayToken ();
						token.start = i;
						token.owner = current;
						current = token;
						i++;
					} else if (ch == ']') {
						var token = current;
						token.end = i;
						current = current.owner;
						current.end = i;
						i++;
						if (current is ArrayToken) {
							if (token is ValueToken) {
								var a = (ArrayToken)current;
								a.values.append (token);
							}
						} else {
							throw new ParseError.SYNTAX ("unexpected ']' %s", current.get_type ().name ());
						}
						
					} else if (ch == ',') {
						var token = current;
						current.end = i;
						current = current.owner;
						current.end = i;
						i++;
						if (current is TupleToken) {
							var tuple = (TupleToken) current;
							tuple.value = token;
							current = current.owner;
							((ObjectToken)current).values.append (tuple);
						} else if (current is ArrayToken) {
							if (token is ValueToken) {
								var array = (ArrayToken)current;
								array.values.append (current);
							}
						} else {
							throw new ParseError.SYNTAX ("syntax error unexpected ',' %s".printf (current.to_string ()));
						}
					} else if (ch == '"') {
						var token = new StringToken ();
						token.start = i;
						i++;
						token.value = parse_string (data, ref i);
						token.end = i;
						token.owner = current;
						current = token;
						i++;
					} else if (ch.isdigit ()) {
						var token = new NumberToken ();
						token.start = i;
						token.value = parse_double (data, ref i);
						token.end = i;
						token.owner = current;
						current = token;
					} else if (ch == 't' || ch == 'f') {
						var token = new BooleanToken ();
						token.start = i;
						token.value = parse_boolean (data, ref i);
						token.end = i;
						token.owner = current;
						current = token;
					} else {
						throw new ParseError.SYNTAX ("syntax error, unexpected char '%c'".printf (ch));
					}
				}
			} catch (Error e) {
				throw new ParseError.SYNTAX ("parse error at char %d: %s".printf (i, e.message));
			}
		}
		
		if (current == null)
			return null;
			
		if (!(current is ObjectToken)) {
			throw new ParseError.SYNTAX ("Root object token not defined (%s: %p), only json with the form { ... } are currently supported".printf (current.get_type ().name (), current));
		}
		return (T?) ((ObjectToken)current).instance;
	}
	
	private void skip_spaces (string data, ref int i) throws ParseError {
		if (i == data.length) {
			return;
		}
		char ch = data[i];
		
		while (ch.isspace ()) {
			i++;
			if (i == data.length) {
				return;
			}
				
			ch = data[i];
		}
	}
	
	private string parse_string (string data, ref int i) throws ParseError {
		if (i == data.length) {
			throw new ParseError.EOF ("Unexpected EOF");
		}
		char ch = data[i];
		var sb = new StringBuilder ();
		
		while (ch != '"') {
			sb.append_c (ch);
			i++;
			if (i == data.length) {
				throw new ParseError.EOF ("Unexpected EOF");
			}
				
			ch = data[i];
		}
		
		return sb.str;
	}
	
	private double parse_double (string data, ref int i) throws Error {
		if (i == data.length) {
			throw new ParseError.EOF ("Unexpected EOF");
		}
		char ch = data[i];
		var sb = new StringBuilder ();
		bool parsing_decimals = false;
		
		while (ch.isdigit () || ch == '.') {
			if (ch == '.') {
				if (parsing_decimals) {
					throw new ParseError.SYNTAX ("syntax error parsing number");
				} else {
					parsing_decimals = true;
				}
			}
			sb.append_c (ch);
			i++;
			if (i == data.length) {
				throw new ParseError.EOF ("Unexpected EOF");
			}
				
			ch = data[i];
		}
		
		return double.parse (sb.str);
	}
	
	private bool parse_boolean (string data, ref int i) throws Error {
		if (i == data.length) {
			throw new ParseError.EOF ("Unexpected EOF");
		}
		char ch = data[i];
		var sb = new StringBuilder ();
		
		while (ch.isalpha ()) {
			sb.append_c (ch);
			i++;
			if (i == data.length) {
				throw new ParseError.EOF ("Unexpected EOF");
			}
				
			ch = data[i];
		}
		
		if (sb.str == "true")
			return true;
		else if (sb.str == "false")
			return false;
		else
			throw new ParseError.SYNTAX ("syntax error parsing boolean");			
	}
}