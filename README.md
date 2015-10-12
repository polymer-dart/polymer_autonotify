# Auto notify support for (yet to be released) polymer 1.0

This package will add support for autonotify in polymer-dart 1.0.
Just add the dependency and add the mixins `PolymerAutoNotifySupportJsBehavior` and `PolymerAutoNotifySupportBehavior` to your `PolymerElement`.
Annotate property with `@observable` (just like in the previous polymer version). 


## notes

Last version works only with modified `observe` you can find [here](https://github.com/dam0vm3nt/observe/tree/reflectable), until the official one gets ported to reflectable or that branch gets merged.

## using the transformer (optional but recommended)

Because `observe` transformer (the modified one to use `reflectable`) use `@observe` annotation to mark properties to be transformed and require a `ChangeNotifier` mixin 
while `polymer-dart` mirror system wants properties to be annotated by `@reflectable` and object to mixin `JsProxy` even though
a unique mirror system is used between `observe` and `polymer-dart` it is required to annotate a class twice (and make it mixin/extend both `JsProxy` AND `Obserable`). 

For example:

```dart

class ThatBeautifulModelOfMine extends Observable with JsProxy {
 @reflectable @observable String field1;
 @reflectable @observable String field2;
}
```

This can be annoying. Expecially if you have many of those classes around that were already annotated for `observe`. 
But don't worry! `polymer_autonotify` come in handy with a nice transformer that should be run *before* `observe` transformer and that will add `polymer-dart` mixin and annotations for you on object already prepared for `observe`. 

This way previous users of `observe` (that already have their object annotated for it) will have nothing to change to use their code with the new `polymer-dart` and `polymer-autonotify`.

In the example before one should only write:
```dart

class TheBeautifulModelOfMine extends Observable {
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
`observe` and `polymer_autonotify` transformer should also be placed in all your imported packages that exports `polymer` your custom components using `autonotify` and exporting models.
