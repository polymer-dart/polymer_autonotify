# Auto notify support for (yet to be released) polymer 1.0

This package will add support for autonotify in polymer-dart 1.0.
Just add the dependency and add the mixins `PolymerAutoNotifySupportJsBehavior` and `PolymerAutoNotifySupportBehavior` to your `PolymerElement`.
Annotate property with `@observable` (just like in the previous polymer version). 


## notes

Last version works only with modified `observe` you can find [here](https://github.com/dam0vm3nt/observe/tree/reflectable), until the official one gets ported to reflectable or that branch gets merged.

## using the transformer (optional)

Because `observe` (modified) and `polymer-dart` use different mirror systems to make an object usable by polymer and with autonotify you have to annotate it twice (and make
it mixin/extend both `JsProxy` AND `Obserable`). For example:
```dart

class ThatBeautifulModelOfMine extends Observable with JsProxy {
 @reflectable @observable String field1;
 @reflectable @observable String field2;
}
```

This can be annoying. So `polymer_autonotify` will come with a nice transformer that should be run *before* `observe` transformer that will add `polymer-dart` mixin and annotations for you on object already annotated for `observe`. 

This way previous users of `observe` (that already have their object annotated for it) will have nothing to change to use their code with `polymer-dart` and `polymer-autonotify`.

In the example before one should only write:
```dart

class TheBeautifulModelOfMine extends Observable {
 @observable String field1;
 @observable String field2;
}
```
