# Thingino MediaPlayer Plugin

# Find curl dependency
curl_dep = dependency('libcurl', required: true)

# Add dependencies to global deps list
deps += curl_dep

# Wake word detection support
message('enable_wake_word option value: ' + get_option('enable_wake_word').to_string())
if get_option('enable_wake_word')
  message('Wake word detection ENABLED - adding ENABLE_WAKE_WORD define')
  # Add ENABLE_WAKE_WORD define for both C and C++
  add_project_arguments('-DENABLE_WAKE_WORD', language: 'c')
  add_project_arguments('-DENABLE_WAKE_WORD', language: 'cpp')
else
  message('Wake word detection DISABLED')
endif

if get_option('enable_wake_word')

  # Find TFLite Micro and ESP MicroSpeech Features libraries
  cc = meson.get_compiler('c')
  tflite_micro_dep = cc.find_library('tflite-micro', required: true)
  microspeech_dep = cc.find_library('esp-microspeech-features', required: true)

  # Add to dependencies
  deps += [tflite_micro_dep, microspeech_dep]

  # CRITICAL: Must define TF_LITE_STATIC_MEMORY to match the library's struct layout
  # The ingenic-tflite-micro library is built with these defines, and TfLiteTensor
  # has a different field order depending on whether this is defined
  add_project_arguments('-DTF_LITE_STATIC_MEMORY', language: 'cpp')
  add_project_arguments('-DTF_LITE_DISABLE_X86_NEON', language: 'cpp')

  # Add include paths for cross-compilation using sysroot from cross file
  sysroot = meson.get_external_property('sys_root', '')
  if sysroot != ''
    # Microspeech headers
    add_project_arguments('-I' + sysroot + '/usr/include/microspeech', language: 'c')
    add_project_arguments('-I' + sysroot + '/usr/include/microspeech', language: 'cpp')
    # Flatbuffers headers (required by TFLite Micro) - use -iquote to help with quoted includes
    add_project_arguments('-iquote' + sysroot + '/usr/include', language: 'cpp')
  endif
endif

# Plugin source files
plugin_sources += files(
    'thingino_media_player.c',
    'media_player_proto.c',
    'switch_proto.c',
    'wake_word.cpp',
)
