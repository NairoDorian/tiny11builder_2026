Place optional payload installer scripts here.
Each .cmd or .ps1 file in this directory is automatically executed
during the first Windows login via SetupComplete.cmd.

Example payloads (inspired by the MOPELotus fork):
  - Microsoft Visual C++ Redistributable packages
  - .NET Framework / .NET Desktop Runtime
  - DirectX Runtime
  - Custom fonts or wallpapers

These files are NOT included in the ISO build itself - they are meant
to be dropped into this folder and then manually copied into the
mounted image's $$\\setup\\scripts\\ folder.
