# payload/packages

Put `*.cmd` and `*.ps1` files here and build with `-Payload`. They run once, as
SYSTEM, at the end of Windows Setup, in alphabetical order (prefix them with
`10-`, `20-`... to control ordering). See [`../README.md`](../README.md).

This README itself is never copied into the image.
