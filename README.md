# Auto notify support for (yet to be released) polymer 1.0

This package will add support for autonotify in polymer-dart 1.0.
Just add the dependency, add the transformer to your pubspec,
use this import in the entry point (`index.dart`):
```
 import "package:smoke/mirrors.dart";
```
and call `useMirrors()` in your main. In `PolymerElement` component add the mixins `PolymerAutoNotifySupportJsBehavior` and `PolymerAutoNotifySupportBehavior` and `Observable`.
Annotate property with `@observable` (just like in the previous polymer version).

Don't worry about mirrors as they will be used only when fast prototyping in Dartium. 
When compiling in JS they will be replaced by a nice static configuration and imports
will be removed by the transformer.

