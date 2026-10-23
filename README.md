TJSON Improved
=====

TJSON Improved is a modified version of [TJSON](https://github.com/JWambaugh/TJSON) that aims to fix common issues, add Quality-of-Life changes, and improved overall performance.

TJSON is a JSON parser that takes inspiration from JavaScript object notation in the sense that it's very tolerant and is capable of accepting a wide variety of syntax errors before stopping the parser entirely.

## Features

In addition to base JSON features, TJSON includes the features below:

- Single quotes (`''`) for Strings or key names.
- Keys don't have to be wrapped in quotes.
- Single-line/C style comments (`//Comment`).
- Multi-line/C++ style comments (`/* Comment */`).
- Commas are optional & Dangling commas are tolerated.
- Class parsing & printing support.
  - Classes parsed with a `TJ_unserialize` static method will be called when the class is ever parsed through a Json.
  - Classes encoded with a `TJ_noEncode` static method can return an array of field names that the class does not want encoded into the Json.

New to TJSON Improved are the features below:

- Enum parsing & printing support, both simple enums and ones with arguments.
- All `Std.is` calls are replace with `Std.isOfType` if Haxe version is 4.2.0 or higher.
- Improved code readability.
- Improved performance.

## Usage

### Installation

Install via Github by running the following in your command line:
```
haxelib git tjson https://github.com/TBar09/TJSON.git
```

### Use in projects

For Haxe projects, simply add:
```
-L tjson
```
For Lime/OpenFL's project.xml, simply add:
```xml
<haxelib name="tjson"/>
```

---

On it's own, using TJSON's static methods will use `haxe.Json` by default. 

In order to use the TJSON parsers/printers, you need to activate them using a define, like so for the command line or hxml files:
```
-D useTJSONParser
-D useTJSONPrinter
```
Or this, if you are using a Project.xml:
```xml
<haxedef name="useTJSONParser"/> <!-- Use the TJSON parser. -->
<haxedef name="useTJSONPrinter"/> <!-- Use the TJSON encoder. -->
```

> [!NOTE]
> The reason why the Haxelib uses defines to activate it's methods is so that someone can freely use `tjson.TJSON.parse` in their code without conditionals or a proxy.
> That way, if you decide to use the `haxe.Json` later on (*Or if a certain target doesn't work well with TJSON*), you can simply remove the `useTJSONParser`/`useTJSONPrinter` define without needing to change all instances of `tjson.TJSON` with `haxe.Json`.

---

```haxe
tjson.TJSON.parse(str:String, ?fileName:String, ?stringProcessor:String->Dynamic):Dynamic
```
Parses a JSON string into a dynamic Haxe object, array, or raw value.

**Parameters:**
- `str`: The JSON string to parse.
- `fileName`: The file name to which the JSON code belongs. Used for generating nice error messages.
- `stringProcessor`: A custom function to process the json string (*Currently unused by the parser*).
  
**Returns:** A Haxe object, array, or raw value.

<br>

```haxe
tjson.TJSON.encode(obj:Dynamic, ?style:EncodingType, ?useCache:Bool):String
```
Serializes a dynamic object or array into a JSON-syntax string.

**Parameters:**
- `obj`: The Haxe object to be serialized.
- `style`: The printing style to use. Options can be `SIMPLE` (No indentation), `FANCY` (Indentation for nesting), or a `CUSTOM` style from a class implementing the `EncodeStyle` interface.
- `useCache`: Whether to cache objects.
  
**Returns:** A JSON-syntax Haxe string.

<br>

> [!NOTE]
> Alongside these functions, `tjson.TJSON.TJSONParser` and `tjson.TJSON.TJSONEncoder` can be called as separate classes if you plan on reusing a parser/printer.

## Examples

Refer to [this page](docs/examples.md) for examples.

License
=======
TJSON Improved is made by T-Bar - 2026

### Original License
Copyright (c) 2012, Jordan CM Wambaugh
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.