# BGE-screen-space-reflections

[blenderartists thread](https://blenderartists.org/t/ssr-screen-space-reflections-shader-v0-7/685927)

This is a 2d filter that does screen-space reflections. Ray to Depth-Buffer intersections are found through a modified raymarch.

The filter expects three properties to be added to the object containing the filter actuator:

Float - roughness (roughness of the reflections)
Float - reflectance (reflectance at normal incidence)
Integer - samples (amount of rays used per pixel)
There are also some settings within the filter that should be modified to match your camera setup. They are around line 20.

NOTE: this filter seems broken when used with an fov other than 90 degrees.

## Screenshots

![sharp reflections](/img/ss_sharp_fresnel.png)
![glossy reflections](/img/ss_glossy_fresnel.png)
![sharp reflections only](/img/ss_sharp_bare.png)
![glossy reflections only](/img/ss_glossy_bare.png)

(taken using Intel Core i7 7500U integrated graphics)

## Credits

This filter uses (or used at some point) the functions used for reconstruction of screen space made by blenderartists.org user martinsh for his deferred render filter, as well as a modification of one of the functions made by blenderartists.org user TheLumCoin.
