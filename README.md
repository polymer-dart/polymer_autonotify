# Auto notify support for (yet to be released) polymer 1.0

This package will add support for autonotify in polymer-dart 1.0.
Just add the dependency and add the mixins `PolymerAutoNotifySupportJsBehavior` and `PolymerAutoNotifySupportBehavior` to your `PolymerElement`.
Annotate property with `@observable` (just like in the previous polymer version). 


## notes

Last version works only with modified `observe` you can find [here](https://github.com/dam0vm3nt/observe/tree/reflectable), until the official one gets ported to reflectable or that branch gets merged.
