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

	/**
	 * Parses a JSON string into a Haxe dynamic object or array.
	 * @param 	json				The JSON string to parse
	 * @param	fileName			The file name to which the JSON code belongs. Used for generating nice error messages
	 * @param	stringProcessor		A custom function to process the json string. Currently unused by the parser.
	 *
	 * @return A Haxe object or array.
	 */
	public static function parse(json:String, ?fileName:String, ?stringProcessor:String->Dynamic):Dynamic {
		#if useTJSONParser
		var t = new TJSONParser(json, fileName, stringProcessor);
		return t.doParse();
		#else
		return haxe.Json.parse(json);
		#end
	}

	/**
	 * Serializes a dynamic object or an array into a JSON string.
	 * @param 	obj				The Haxe object to be serialized.
	 * @param	style			The printing style to use. Can be SIMPLE (No indentation),
	 *							FANCY (Indentation for nesting), or a CUSTOM style from a class
	 *							implementing the EncodeStyle interface.
	 * @param	useCache		Whether to cache objects.
	 *
	 * @return A Haxe json string.
	 */
	public static function encode(obj:Dynamic, ?style:EncodingType, ?useCache:Bool):String {
		#if useTJSONPrinter
		var t = new TJSONEncoder(useCache);
		return t.doEncode(obj, style);
		#else
		return haxe.Json.stringify(obj, null, (style == FANCY ? "\t" : ""));
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

	public function new(vjson:String, ?vfileName:String = "JSON Data", ?stringProcessor:String->Dynamic = null) {
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
			//determine if objector array
			return switch (getNextSymbol()) {
				case '{': doObject();
				case '[': doArray();
				case s: convertStringToType(s);
			}
		} catch(e:String) {
			throw fileName + " on line " + currentLine + ": " + e;
		}
	}

	private function doObject():Dynamic {
		var obj:Dynamic = {};

		var val:Dynamic = '';
		var key:String;

		var isClassOb:Bool = false;
		cache.push(obj);

		while(pos < json.length) {
			key = getNextSymbol();

			if(key == "," && !lastSymbolQuoted) continue;
			if(key == "}" && !lastSymbolQuoted) {
				//end of the object. Run the TJ_unserialize function if there is one
				if(isClassOb &&
					#if(flash9) try obj.TJ_unserialize != null catch( e : Dynamic ) false
					#elseif(cs || java) Reflect.hasField(obj, "TJ_unserialize") #else (obj.TJ_unserialize != null) #end) {
					obj.TJ_unserialize();
				}

				return obj;
			}

			var seperator:String = getNextSymbol();
			if(seperator != ":") {
				throw "Expected ':' but got '" + seperator + "' instead.";
			}

			var v:String = getNextSymbol();
			if(key == TJSON.HAXE_CLASS_REFERENCE_PREFIX) {
				var cls:Class<Dynamic> = Type.resolveClass(v);
				if(cls == null) throw "Invalid class name - " + v;

				obj = Type.createEmptyInstance(cls);

				cache.pop();
				cache.push(obj);
				isClassOb = true;

				continue;
			}

			if(v == "{" && !lastSymbolQuoted) // Another object
			{
				val = doObject();
			}
			else if(v == "[" && !lastSymbolQuoted) // Array
			{
				val = doArray();
			}
			else // Anything else
			{
				val = convertStringToType(v);
			}

			Reflect.setField(obj, key, val);
		}

		throw "Unexpected end of file. Expected '}'";
	}

	private function doArray():Dynamic {
		var a:Array<Dynamic> = new Array<Dynamic>();
		var val:Dynamic;

		while(pos < json.length) {
			val = getNextSymbol();
			if(val == ',' && !lastSymbolQuoted)
			{
				continue;
			}
			else if(val == ']' && !lastSymbolQuoted)
			{
				return a;
			}
			else if(val == "{" && !lastSymbolQuoted)
			{
				val = doObject();
			}
			else if(val == "[" && !lastSymbolQuoted)
			{
				val = doArray();
			}
			else
			{
				val = convertStringToType(val);
			}

			a.push(val);
		}

		throw "Unexpected end of file. Expected ']'";
	}

	/**
	 * Converts a string into a type that is supported by JSON.
	 */
	private function convertStringToType(symbol:String):Dynamic {
		if(lastSymbolQuoted) // Strings
		{
			//value was in quotes, so it's a string.
			//look for reference prefix, return cached reference if it is
			if(StringTools.startsWith(symbol, TJSON.OBJECT_REFERENCE_PREFIX)){
				var idx:Int = Std.parseInt(symbol.substr(TJSON.OBJECT_REFERENCE_PREFIX.length));
				return cache[idx];
			}

			return symbol; //just a normal string so return it
		}
		else if(looksLikeFloat(symbol)) // Float
		{
			return Std.parseFloat(symbol);
		}
		else if(looksLikeInt(symbol)) // Int
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


	private inline function looksLikeFloat(s:String):Bool {
		return floatRegex.match(s) || (
			intRegex.match(s) && {
				var intStr = intRegex.matched(0);
				if (intStr.charCodeAt(0) == "-".code)
					intStr > "-2147483648";
				else
					intStr > "2147483647";
			}
		);
	}

	private inline function looksLikeInt(s:String):Bool {
		return intRegex.match(s);
	}

	private function getNextSymbol():String {
		lastSymbolQuoted = false;
		var c:String = '';
		var inQuote:Bool = false;
		var quoteType:String = "";
		var symbol:String = '';
		var inEscape:Bool = false;
		var inSymbol:Bool = false;
		var inLineComment:Bool = false;
		var inBlockComment:Bool = false;

		while(pos < json.length) {
			c = json.charAt(pos++);

			if(c == "\n" && !inSymbol) currentLine++;
			if(inLineComment) {
				if(c == "\n" || c == "\r") {
					inLineComment = false;
					pos++;
				}
				continue;
			}

			if(inBlockComment) {
				if(c == "*" && json.charAt(pos) == "/") {
					inBlockComment = false;
					pos++;
				}
				continue;
			}

			if(inQuote) {
				if(inEscape) {
					inEscape = false;
					if(c == "'" || c == '"') { // " or '
						symbol += c;
						continue;
					}
					else if(c == "t") {
						symbol += "\t";
						continue;
					}
					else if(c == "n") {
						symbol += "\n";
						continue;
					}
					else if(c == "\\") {
						symbol += "\\";
						continue;
					}
					else if(c == "r") {
						symbol += "\r";
						continue;
					}
					else if(c == "/") {
						symbol += "/";
						continue;
					}
					else if(c == "u") {
						var hexValue:Int = 0;

						for (i in 0...4) {
							if (pos >= json.length) {
								throw "Unfinished UTF8 character";
							}

							var nc:Int = json.charCodeAt(pos++);
							hexValue = hexValue << 4;

							if (nc >= '0'.code && nc <= '9'.code) { /* 0..9 */
								hexValue += nc - 48;
							} else if (nc >= 'A'.code && nc <= 'F'.code) { /* A..F */
								hexValue += 10 + nc - 65;
							} else if (nc >= 'a'.code && nc <= 'f'.code) {/* a..f */
								hexValue += 10 + nc - 95;
							} else {
								throw "Not a hex digit";
							}
						}

						symbol += String.fromCharCode(hexValue);

						continue;
					}


					throw "Invalid escape sequence '\\" + c + "'";
				} else {
					if(c == "\\") {
						inEscape = true;
						continue;
					}
					if(c == quoteType) {
						return symbol;
					}

					symbol += c;
					continue;
				}
			}
			else if(c == "/") //handle comments
			{
				var c2 = json.charAt(pos);
				//handle single line comments.
				//These can even interrupt a symbol.
				if(c2 == "/"){
					inLineComment = true;
					pos++;
					continue;
				}

				//handle block comments.
				//These can even interrupt a symbol.
				else if(c2 == "*") {
					inBlockComment = true;
					pos++;
					continue;
				}
			}



			if (inSymbol) {
				if(c == ' ' || c == "\n" || c == "\r" || c == "\t" || c == ',' || c == ":" || c == "}" || c == "]") { //end of symbol, return it
					pos--;
					return symbol;
				}else{
					symbol += c;
					continue;
				}
			} else {
				if(c == ' ' || c == "\t" || c == "\n" || c == "\r"){
					continue;
				}

				if(c == "{" || c == "}" || c == "[" || c == "]" || c == "," || c == ":") {
					return c;
				}

				if(c == "'" || c == '"'){
					inQuote = true;
					quoteType = c;
					lastSymbolQuoted = true;
					continue;
				} else {
					inSymbol = true;
					symbol = c;
					continue;
				}
			}

		} // end of while. We have reached EOF if we are here.

		if(inQuote) {
			throw "Unexpected end of data. Expected ( " + quoteType + " )";
		}

		return symbol;
	}


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
		if(uCache) cache = new Array();
	}

	public function doEncode(obj:Dynamic, ?style:EncodingType = SIMPLE) {
		if(!Reflect.isObject(obj)) {
			throw("Provided object is not an object.");
		}

		var st:EncodeStyle;
		switch(style) {
			case CUSTOM(encSty): //Custom printing
				st = encSty;
			case FANCY: //Fancy printing
				st = new FancyStyle();
			default: //Simple printing
				st = new SimpleStyle();
		}

		var buffer = new StringBuf();
		if(isOfType(obj, Array) || isOfType(obj, List))
		{
			buffer.add(encodeIterable(obj, st, 0));
		}
		else if(isOfType(obj, haxe.ds.StringMap))
		{
			buffer.add(encodeMap(obj, st, 0));
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
		var buffer = new StringBuf();
		buffer.add(style.beginObject(depth));

		var fieldCount = 0;
		var fields:Array<String>;
		var dontEncodeFields:Array<String> = null;

		var cls = Type.getClass(obj);
		if (cls != null) fields = Type.getInstanceFields(cls);
		else fields = Reflect.fields(obj);

		/*
		preserve class name when serializing class objects
		is there a way to get c outside of a switch?
		*/
		switch(Type.typeof(obj)) {
			case TClass(c):
				if(fieldCount++ > 0) buffer.add(style.entrySeperator(depth));
				else buffer.add(style.firstEntry(depth));

				buffer.add('"' + TJSON.HAXE_CLASS_REFERENCE_PREFIX + '"' + style.keyValueSeperator(depth));
				buffer.add(encodeValue(Type.getClassName(c), style, depth));

				if( #if flash9 try obj.TJ_noEncode != null catch( e : Dynamic ) false #elseif (cs || java) Reflect.hasField(obj, "TJ_noEncode") #else obj.TJ_noEncode != null #end ) {
					dontEncodeFields = obj.TJ_noEncode();
				}
			default:
		}

		for (field in fields) {
			if(dontEncodeFields != null && dontEncodeFields.indexOf(field) >= 0) continue;

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


	private function cacheEncode(value:Dynamic):String{
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
		if(isOfType(value, Int) || isOfType(value, Float)) //Numbers
		{
			return Std.string(value);
		}
		else if(isOfType(value, Array) || isOfType(value, List)) //Arrays / Lists
		{
			var v:Array<Dynamic> = value;
			return encodeIterable(v, style, depth + 1);
		}
		else if(isOfType(value, List)) //Lists
		{
			var v:List<Dynamic> = value;
			return encodeIterable(v, style, depth + 1);
		}
		else if(isOfType(value, haxe.ds.StringMap)) //String maps
		{
			return encodeMap(value, style, depth + 1);
		}
		else if(isOfType(value, String)) //Strings
		{
			return('"' + Std.string(value).replace("\\","\\\\").replace("\n","\\n").replace("\r","\\r").replace('"','\\"') + '"');
		}
		else if(isOfType(value, Bool)) //Bools
		{
			return (value == true ? "true" : "false");
		}
		else if(Reflect.isObject(value)) //Objects
		{
			var ret = cacheEncode(value);
			if(ret != null) return ret;

			return encodeObject(value, style, depth + 1);
		}
		else if(value == null) //Null
		{
			return "null";
		}
		else
		{
			return null;
		}
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
		return charTimesN(depth + 1) + ' ';
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