# Auto notify support for (yet to be released) polymer-dart 1.0
a.k.a. : get rid of all those fancy `set`, `add`, `remove`, etc. calls


## the problem 

In `polymer` 1.0 you have to call a bunch of API (`set` and list accessor methods) on the polymer component whenever you have to apply a change on the model instead of changing the model directly. To make things worse if you have
two or more independent components, for example two different views of the same model that are not inheriting the model one from the other by means of binding constructs (i.e. `{{ }}` or
 `[[ ]]`), then you will have to call those API on each of component.
 
Other then being very annoying this makes nearly impossible to follow consolidated patterns like MVC when building an app using vanilla polymer 1.0 : 
infact the controller (C) should always interact directly with the view (V) to update the model (M).

The opposite is true for `polymer` before 1.0 and that's one of the reason many appreciated that framework even though it was slower and less browser independent.

## enters `autonotify`

This package will add support for autonotify in polymer-dart 1.0, making it possible to write your code more or less in the same way you used to do with previous `polymer` version.

You just have to annotate properties with `@observable` and extend/mixin the familiar `Observable` mixin, exactly like before, and `polymer_autnotify` will take care of calling `polymer` accessor API 
 automatically for you.

To enable the autonotify feature just add the dependency to your project and add the mixin `AutonotifyBehavior` to your `PolymerElement` then 
annotate property with `@observable` (just like in the previous polymer version). 


## notes

Latest version of this library will not depend anymore on the old `smoke` mirroring system but requires a modified `observe` that you can find [here](https://github.com/dam0vm3nt/observe/tree/reflectable), 
 until the official one gets ported to reflectable or that branch gets merged.

## using the transformer (optional but recommended)

Because `observe` transformer (the modified one to use `reflectable`) uses `@observe` annotation to mark properties to be transformed and requires a `ChangeNotifier` mixin 
while `polymer-dart` mirror system requires properties to be annotated by `@reflectable` and object to mixin `JsProxy` even though
a unique mirror system is now being used between `observe` and `polymer-dart` it is required to annotate a class twice (and make it mixin/extend both `JsProxy` AND `Obserable`). 

For example:

```dart

class ThatBeautifulModelOfMine extends Observable with JsProxy {
 @reflectable @observable String field1;
 @reflectable @observable String field2;
}
```

This can be annoying. Expecially if you have many of those classes around that were already annotated for `observe`. 
But don't worry! `polymer_autonotify` come in handy with a nice transformer that have to be run *before* `observe` transformer and that will add `polymer-dart` mixin and annotations for you on object already prepared for `observe`. 

This way previous users of `observe` (that already have their object annotated for it) will have nothing to change to use their code with the new `polymer-dart` and `polymer-autonotify`.

In the example before one should only write:
```dart

class ThatBeautifulModelOfMine extends Observable {
 @observable String field1;
 @observable String field2;
}
```

If you want to use it your main `pubspec.yaml` should appear like this :
```yaml
...


- web_components:
    entry_points:
    - web/index.html
- polymer_autonotify
- observe
- reflectable:
    entry_points:
    - web/index.dart

...
```
`observe` and `polymer_autonotify` transformer should also be placed in all your imported packages that exports custom `polymer` components using `autonotify` and/or exporting models object extending/mixing `Observe`.

## Recent Changes


Current version is retro-compatible but you can now use only one behavior (i.e.: `AutonotifyBehavior`) instead of the two.

Added some polite tests. You can run them starting a  `pub serve` instance and then `pub run test --pub-serve=8080 -p dartium`. Also in tests you can find a simple sample on how to use this feature.
