package tjson;

#if (haxe_ver >= 4.2)
import Std.isOfType;
#else
import Std.is as isOfType;
#end

using StringTools;
class TJSON {
	public static inline var OBJECT_REFERENCE_PREFIX:String = "@~obRef#";

	public static inline var HAXE_CLASS_REFERENCE_PREFIX:String = "_hxcls";
	public static inline var HAXE_ENUM_REFERENCE_PREFIX:String = "_hxenm";

	/**
	 * Parses a JSON string into a dynamic Haxe object, array, or raw value.
	 *
	 * @param 	str					The JSON string to parse.
	 * @param	fileName			The file name to which the JSON code belongs.
	 *								Used for generating nice error messages
	 * @param	stringProcessor		A custom function to process the json string.
	 *								Currently unused by the parser.
	 *
	 * @return	A Haxe object, array, or raw value.
	 */
	public static function parse(str:String, ?fileName:String, ?stringProcessor:String->Dynamic):Dynamic {
		#if useTJSONParser
		var t = new TJSONParser(str, fileName, stringProcessor);
		return t.doParse();
		#else
		return haxe.Json.parse(str);
		#end
	}

	/**
	 * Serializes a dynamic object or array into a JSON-syntax string.
	 *
	 * @param 	obj				The Haxe object to be serialized.
	 * @param	style			The printing style to use. Can be `SIMPLE` (No indentation),
	 *							`FANCY` (Indentation for nesting), or a `CUSTOM` style from a
	 *							class implementing the `EncodeStyle` interface.
	 * @param	useCache		Whether to cache objects.
	 *
	 * @return	A JSON-syntax Haxe string.
	 */
	public static function encode(obj:Dynamic, ?style:EncodingType, ?useCache:Bool):String {
		#if useTJSONPrinter
		var t = new TJSONEncoder(useCache);
		return t.doEncode(obj, style);
		#else
		return haxe.Json.stringify(obj, null, (style == FANCY ? "\t" : null));
		#end
	}
}

enum EncodingType {
	SIMPLE;
	FANCY;
	CUSTOM(encSty:EncodeStyle);
}

/* JSON Parser */

class TJSONParser {
	var pos:Int;
	var currentLine:Int;

	var json:String;
	var fileName:String;

	var lastSymbolQuoted:Bool; //true if the last symbol was in quotes.
	var floatRegex:EReg;
	var intRegex:EReg;

	var cache:Array<Dynamic>;
	var strProcessor:String->Dynamic;

	public function new(vjson:String, ?vfileName:String = "TJSON.json", ?stringProcessor:String->Dynamic = null) {
		this.json = vjson;
		this.fileName = vfileName;
		this.currentLine = 1;
		this.pos = 0;

		this.lastSymbolQuoted = false;

		this.floatRegex = ~/^-?[0-9]*\.[0-9]+$/;
		this.intRegex = ~/^-?[0-9]+$/;

		this.strProcessor = (stringProcessor == null ? defaultStringProcessor : stringProcessor);
		this.cache = new Array();
	}

	public function doParse():Dynamic {
		try {
			// Determine if object, array, or raw type.
			return switch(getNextSymbol()) {
				case '{': doObject();
				case '[': doArray();
				case s: convertStringToType(s);
			}
		} catch(e:String) {
			throw (fileName != null ? fileName : "FILE.json") + " on line " + currentLine + ": " + e;
		}
	}

	private function doObject():Dynamic {
		var obj:Dynamic = {};

		var val:Dynamic = '';
		var key:String;

		var isClassOb:Bool = false;
		var isEnumOb:Bool = false;
		var enmInfo:Map<String, Dynamic> = null;

		cache.push(obj);

		while(pos < json.length) {
			key = getNextSymbol();

			if(key == "," && !lastSymbolQuoted) continue;
			if(key == "}" && !lastSymbolQuoted) {
				/* End of the object */

				if(isClassOb && hasUnserializeFunc(obj)) // If it's a class object, run it's `TJ_unserialize` function, if present
				{
					obj.TJ_unserialize();
				}
				else if(isEnumOb) // If it's an enum object, we create the enum instance and return it
				{
					// If no `arguments` field was set, we just leave it blank
					if(!enmInfo.exists("arguments")) enmInfo.set("arguments", []);

					obj = Type.createEnum(obj, enmInfo.get("name"), enmInfo.get("arguments"));
				}

				return obj;
			}

			var seperator:String = getNextSymbol();
			if(seperator != ":") {
				throw "Expected ':' but got '" + seperator + "' instead";
			}

			var v:String = getNextSymbol();
			if(key == TJSON.HAXE_CLASS_REFERENCE_PREFIX && !isEnumOb) // The key has the Haxe class reference key, so it's a class
			{
				var cls:Class<Dynamic> = Type.resolveClass(v);
				if(cls == null) throw "Invalid class name - " + v;

				obj = Type.createEmptyInstance(cls);

				cache.pop();
				cache.push(obj);
				isClassOb = true;

				continue;
			}
			else if(key == TJSON.HAXE_ENUM_REFERENCE_PREFIX && !isClassOb) // The key has the Haxe enum reference key, so it's an enum
			{
				var enm:Enum<Dynamic> = Type.resolveEnum(v);
				if(enm == null) throw "Invalid enum name - " + v;

				enmInfo = [];
				obj = enm;

				cache.pop();
				cache.push(obj);
				isEnumOb = true;

				continue;
			}

			if(v == "{" && !lastSymbolQuoted) // An opening curly bracket, start object inside object
			{
				val = doObject();
			}
			else if(v == "[" && !lastSymbolQuoted) // An opening bracket, start array inside object
			{
				val = doArray();
			}
			else // We convert the value into it's proper type
			{
				val = convertStringToType(v);
			}

			// We are inside an enum declaration
			if(isEnumOb) {
				if(key == "name" || key == "arguments")
				{
					enmInfo.set(key, val);
				}

				continue;
			}

			Reflect.setField(obj, key, val);
		}

		throw "Unexpected end of file. Expected '}'";
	}

	private function doArray():Dynamic {
		var arr:Array<Dynamic> = new Array<Dynamic>();
		var val:Dynamic;

		while(pos < json.length) {
			val = getNextSymbol();

			if(val == ',' && !lastSymbolQuoted) // A comma, stop last value and start new one
			{
				continue;
			}
			else if(val == ']' && !lastSymbolQuoted) // A closing bracket, stop array reading and return it
			{
				return arr;
			}
			else if(val == "{" && !lastSymbolQuoted) // An opening curly bracket, start object inside array
			{
				val = doObject();
			}
			else if(val == "[" && !lastSymbolQuoted) // An opening bracket, start array inside array
			{
				val = doArray();
			}
			else // Anything else, we convert the value into it's proper type
			{
				val = convertStringToType(val);
			}

			arr.push(val);
		}

		throw "Unexpected end of file. Expected ']'";
	}

	/**
	 * Converts a string into a type that is supported by JSON.
	 */
	private function convertStringToType(symbol:String):Dynamic {
		if(lastSymbolQuoted) // String
		{
			/* The value was in quotes, so it's a string. We look
			for the reference prefix, and return the cached reference if it is. */
			if(StringTools.startsWith(symbol, TJSON.OBJECT_REFERENCE_PREFIX)){
				var idx:Int = Std.parseInt(symbol.substr(TJSON.OBJECT_REFERENCE_PREFIX.length));
				return cache[idx];
			}

			return symbol; // It's just a normal string, so return it.
		}
		else if(canBeFloat(symbol)) // Float
		{
			return Std.parseFloat(symbol);
		}
		else if(canBeInt(symbol)) // Int
		{
			return Std.parseInt(symbol);
		}
		else if(symbol == "true" || symbol == "false") // Bool
		{
			return (symbol == "true");
		}
		else if(symbol == "null") // Null
		{
			return null;
		}

		return symbol;
	}

	/**
	 * Checks whether `obj` has the `TJ_unserialize` function.
	 */
	private inline function hasUnserializeFunc(obj:Dynamic):Bool {
		#if(flash9)
		return try obj.TJ_unserialize != null catch( e : Dynamic ) false;
		#elseif(cs || java)
		return Reflect.hasField(obj, "TJ_unserialize");
		#else
		return (obj.TJ_unserialize != null);
		#end
	}

	/**
	 * Returns whether the given string can be a Float.
	 */
	private inline function canBeFloat(s:String):Bool {
		return floatRegex.match(s) || (
			canBeInt(s) && {
			var intStr:String = intRegex.matched(0);
			intStr > (intStr.charCodeAt(0) == '-'.code ? "-2147483648" : "2147483647");
		});
	}

	/**
	 * Returns whether the given string can be a Integer.
	 */
	private inline function canBeInt(s:String):Bool {
		return intRegex.match(s);
	}

	private function getNextSymbol():String {
		lastSymbolQuoted = false;

		var c:Int = 0;
		var inQuote:Bool = false;
		var quoteType:Int = 0;
		var symbol:String = '';
		var inEscape:Bool = false;
		var inSymbol:Bool = false;
		var inLineComment:Bool = false;
		var inBlockComment:Bool = false;

		while(pos < json.length) {
			c = json.fastCodeAt(pos++);

			if(c == "\n".code && !inSymbol) currentLine++;
			if(inLineComment) {
				if(c == "\n".code || c == "\r".code) {
					inLineComment = false;
					pos++;
				}
				continue;
			}

			if(inBlockComment) {
				if(c == '*'.code && json.fastCodeAt(pos) == '/'.code) {
					inBlockComment = false;
					pos++;
				}
				continue;
			}

			if(inQuote) {
				if(inEscape) {
					inEscape = false;
					if(c == "'".code || c == '"'.code) {
						symbol += String.fromCharCode(c);
						continue;
					}
					else if(c == 't'.code) {
						symbol += "\t";
						continue;
					}
					else if(c == 'n'.code) {
						symbol += "\n";
						continue;
					}
					else if(c == "\\".code) {
						symbol += "\\";
						continue;
					}
					else if(c == 'r'.code) {
						symbol += "\r";
						continue;
					}
					else if(c == '/'.code) {
						symbol += "/";
						continue;
					}
					else if(c == 'u'.code) {
						var hexValue:Int = 0;

						for (i in 0...4) {
							if (pos >= json.length) {
								throw "Unfinished UTF8 character";
							}

							var nc:Int = json.fastCodeAt(pos++);
							hexValue = hexValue << 4;

							if (nc >= '0'.code && nc <= '9'.code) { /* 0..9 */
								hexValue += nc - 48;
							} else if (nc >= 'A'.code && nc <= 'F'.code) { /* A..F */
								hexValue += 10 + nc - 65;
							} else if (nc >= 'a'.code && nc <= 'f'.code) { /* a..f */
								hexValue += 10 + nc - 95;
							} else {
								throw "Not a hex digit";
							}
						}

						symbol += String.fromCharCode(hexValue);

						continue;
					}

					throw "Invalid escape sequence '\\" + String.fromCharCode(c) + "'";
				} else {
					if(c == "\\".code) {
						inEscape = true;
						continue;
					}
					if(c == quoteType) {
						return symbol;
					}

					symbol += String.fromCharCode(c);
					continue;
				}
			}
			else if(c == '/'.code) // Handle both types of comments. These can even interrupt a symbol
			{
				var c2 = json.fastCodeAt(pos);
				// Handle single line comments
				if(c2 == '/'.code){
					inLineComment = true;
					pos++;
					continue;
				}

				// Handle multi-line/block comments
				else if(c2 == '*'.code) {
					inBlockComment = true;
					pos++;
					continue;
				}
			}


			if (inSymbol) {
				// End of symbol, return it
				if(c == ' '.code || c == "\n".code || c == "\r".code || c == "\t".code || c == ','.code || c == ':'.code || c == '}'.code || c == ']'.code) {
					pos--;
					return symbol;
				} else {
					symbol += String.fromCharCode(c);
					continue;
				}
			} else {
				if(c == ' '.code || c == "\t".code || c == "\n".code || c == "\r".code) {
					continue;
				}

				if(c == '{'.code || c == '}'.code || c == '['.code || c == ']'.code || c == ','.code || c == ':'.code) {
					return String.fromCharCode(c);
				}

				if(c == "'".code || c == '"'.code) {
					inQuote = true;
					quoteType = c;
					lastSymbolQuoted = true;
					continue;
				} else {
					inSymbol = true;
					symbol = String.fromCharCode(c);
					continue;
				}
			}
		} // End of while loop. We have reached EOF if we are here.

		if(inQuote) {
			throw "Unexpected end of data. Expected ( " + String.fromCharCode(quoteType) + " )";
		}

		return symbol;
	}

	// CURRENTLY UNUSED
	private inline function defaultStringProcessor(str:String):Dynamic {
		return str;
	}
}

/* JSON Printer */

class TJSONEncoder {
	var cache:Array<Dynamic>;
	var uCache:Bool;

	public function new(useCache:Bool = true) {
		uCache = useCache;
		if(uCache) cache = new Array<Dynamic>();
	}

	public function doEncode(obj:Dynamic, ?style:EncodingType) {
		if(!Reflect.isObject(obj) && !Reflect.isEnumValue(obj)) {
			throw "Provided variable is not an object";
		}

		var st:EncodeStyle = switch(style) {
			case CUSTOM(encSty): encSty; // Custom printing
			case FANCY: new FancyStyle(); // Fancy printing
			default: new SimpleStyle(); // Simple printing
		}

		var buffer:StringBuf = new StringBuf();
		if(isOfType(obj, Array) || isOfType(obj, List)) // Array or List
		{
			buffer.add(encodeIterable(obj, st, 0));
		}
		else if(isOfType(obj, haxe.ds.StringMap)) // String Map
		{
			buffer.add(encodeMap(obj, st, 0));
		}
		else if(Reflect.isEnumValue(obj)) // Enum instance
		{
			cacheEncode(obj);
			buffer.add(encodeEnum(obj, st, 0));
		}
		else
		{
			cacheEncode(obj);
			buffer.add(encodeObject(obj, st, 0));
		}

		return buffer.toString();
	}

	/* Encoding different types */

	private function encodeObject(obj:Dynamic, style:EncodeStyle, depth:Int):String {
		var buffer:StringBuf = new StringBuf();
		buffer.add(style.beginObject(depth));

		var fieldCount:Int = 0;
		var fields:Array<String>;
		var blacklistedFields:Array<String> = null;

		var cls:Class<Dynamic> = Type.getClass(obj);
		fields = (cls != null ? Type.getInstanceFields(cls) : Reflect.fields(obj));

		/* Preserve class name when serializing class objects.
		Is there a way to get `c` outside of a switch? */
		switch(Type.typeof(obj)) {
			case TClass(c):
				if(fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
				else buffer.add(style.firstEntry(depth));

				buffer.add('"' + TJSON.HAXE_CLASS_REFERENCE_PREFIX + '"' + style.keyValueSeperator(depth));
				buffer.add(encodeValue(Type.getClassName(c), style, depth));

				if(hasNoEncodeFunc(obj)) {
					blacklistedFields = obj.TJ_noEncode();
				}

			default:
		}

		for (field in fields) {
			if(blacklistedFields != null && blacklistedFields.indexOf(field) >= 0) continue;

			var value:Dynamic = Reflect.field(obj, field);
			var vStr:String = encodeValue(value, style, depth);

			if(vStr != null) {
				if(fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
				else buffer.add(style.firstEntry(depth));

				buffer.add('"' + field + '"' + style.keyValueSeperator(depth) + vStr);
			}
		}

		buffer.add(style.endObject(depth));
		return buffer.toString();
	}

	private function encodeEnum(obj:EnumValue, style:EncodeStyle, depth:Int):String {
		var buffer:StringBuf = new StringBuf();
		buffer.add(style.beginObject(depth));

		// First we encode the enum reference so the parser picks it up first
		switch(Type.typeof(obj)) {
			case TEnum(e):
				buffer.add(style.firstEntry(depth));

				buffer.add('"' + TJSON.HAXE_ENUM_REFERENCE_PREFIX + '"' + style.keyValueSeperator(depth));
				buffer.add(encodeValue(Type.getEnumName(e), style, depth));

			default:
		}

		// Then we do the enum instance name
		buffer.add(style.entrySeperator(depth));
		buffer.add('"name"' + style.keyValueSeperator(depth) + encodeValue(Type.enumConstructor(obj), style, depth));

		// Lastly, we do the arguments, if any
		var enumValueArguments:Array<Dynamic> = Type.enumParameters(obj);
		if(enumValueArguments != null && enumValueArguments.length > 0) {
			buffer.add(style.entrySeperator(depth));
			buffer.add('"arguments"' + style.keyValueSeperator(depth) + encodeValue(enumValueArguments, style, depth));
		}

		buffer.add(style.endObject(depth));
		return buffer.toString();
	}

	private function encodeMap(obj:Map<Dynamic, Dynamic>, style:EncodeStyle, depth:Int):String {
		var buffer = new StringBuf();
		buffer.add(style.beginObject(depth));

		var fieldCount = 0;
		for (field in obj.keys()) {
			if(fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
			else buffer.add(style.firstEntry(depth));

			var value:Dynamic = obj.get(field);
			buffer.add('"' + field + '"' + style.keyValueSeperator(depth));
			buffer.add(encodeValue(value, style, depth));
		}

		buffer.add(style.endObject(depth));
		return buffer.toString();
	}


	private function encodeIterable(obj:Iterable<Dynamic>, style:EncodeStyle, depth:Int):String {
		var buffer = new StringBuf();
		buffer.add(style.beginArray(depth));

		var fieldCount = 0;
		for (value in obj){
			if(fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
			else buffer.add(style.firstEntry(depth));

			buffer.add(encodeValue(value, style, depth));
		}

		buffer.add(style.endArray(depth));
		return buffer.toString();
	}


	private function cacheEncode(value:Dynamic):String {
		if(!uCache) return null;

		for(c in 0...cache.length){
			if(cache[c] == value){
				return '"' + TJSON.OBJECT_REFERENCE_PREFIX + c + '"';
			}
		}

		cache.push(value);
		return null;
	}


	private function encodeValue(value:Dynamic, style:EncodeStyle, depth:Int):String {
		if(isOfType(value, Int) || isOfType(value, Float)) // Numbers
		{
			return Std.string(value);
		}
		else if(isOfType(value, Array) || isOfType(value, List)) // Arrays / Lists
		{
			var v:Array<Dynamic> = value;
			return encodeIterable(v, style, depth + 1);
		}
		else if(isOfType(value, List)) // Lists
		{
			var v:List<Dynamic> = value;
			return encodeIterable(v, style, depth + 1);
		}
		else if(isOfType(value, haxe.ds.StringMap)) // String maps
		{
			return encodeMap(value, style, depth + 1);
		}
		else if(isOfType(value, String)) // Strings
		{
			return ('"' + Std.string(value).replace("\\","\\\\").replace("\n","\\n").replace("\r","\\r").replace('"','\\"') + '"');
		}
		else if(isOfType(value, Bool)) // Bools
		{
			return (value == true ? "true" : "false");
		}
		else if(Reflect.isObject(value)) // Objects, Classes, and Enum instances
		{
			var ret = cacheEncode(value);
			if(ret != null) return ret;

			return encodeObject(value, style, depth + 1);
		}
		else if(value == null) // Null
		{
			return "null";
		}
		else if(Reflect.isEnumValue(value))
		{
			var ret = cacheEncode(value);
			if(ret != null) return ret;

			return encodeEnum(value, style, depth + 1);
		}
		else
		{
			return null;
		}
	}

	/**
	 * Checks whether `obj` has the `TJ_noEncode` function.
	 */
	private inline function hasNoEncodeFunc(obj:Dynamic):Bool {
		#if(flash9)
		return try obj.TJ_noEncode != null catch( e : Dynamic ) false;
		#elseif(cs || java)
		return Reflect.hasField(obj, "TJ_noEncode");
		#else
		return (obj.TJ_unserialize != null);
		#end
	}
}


interface EncodeStyle {
	public function beginObject(depth:Int):String;
	public function endObject(depth:Int):String;
	public function beginArray(depth:Int):String;
	public function endArray(depth:Int):String;
	public function firstEntry(depth:Int):String;
	public function entrySeperator(depth:Int):String;
	public function keyValueSeperator(depth:Int):String;
}


class SimpleStyle implements EncodeStyle {
	public function new() {}

	public function beginObject(depth:Int):String {
		return "{";
	}
	public function endObject(depth:Int):String {
		return "}";
	}
	public function beginArray(depth:Int):String {
		return "[";
	}
	public function endArray(depth:Int):String {
		return "]";
	}
	public function firstEntry(depth:Int):String {
		return "";
	}
	public function entrySeperator(depth:Int):String {
		return ",";
	}
	public function keyValueSeperator(depth:Int):String {
		return ":";
	}
}

class FancyStyle implements EncodeStyle {
	public var tab(default, null):String;
	public function new(tab:String = "\t") {
		this.tab = tab;
		charTimesNCache = [""];
	}

	public function beginObject(depth:Int):String {
		return "{\n";
	}
	public function endObject(depth:Int):String {
		return "\n" + charTimesN(depth) + "}";
	}
	public function beginArray(depth:Int):String {
		return "[\n";
	}
	public function endArray(depth:Int):String {
		return "\n" + charTimesN(depth) + "]";
	}
	public function firstEntry(depth:Int):String {
		return charTimesN(depth + 1);
	}
	public function entrySeperator(depth:Int):String {
		return ",\n" + charTimesN(depth + 1);
	}
	public function keyValueSeperator(depth:Int):String {
		return ": ";
	}

	private var charTimesNCache:Array<String>;
	private function charTimesN(n:Int):String {
		return if (n < charTimesNCache.length) {
			charTimesNCache[n];
		} else {
			charTimesNCache[n] = charTimesN(n - 1) + tab;
		}
	}
}