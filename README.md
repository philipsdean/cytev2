# 🧐 Cyte

[![Xcode - Build and Analyze](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml/badge.svg)](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) 
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cataddict42.svg?style=social&label=%20%40CatAddict42)](https://twitter.com/cataddict42)

🚧 Work in progress - this is beta software, use with care

A background screen recorder for easy history search. 
If you choose to supply an OpenAI key, or a local language model like LLaMA, it can act as a knowledge base. Be aware that transcriptions will be sent to OpenAI when you chat if you provide an OpenAI API key.

![Cyte Screenshot](assets/images/cyte.gif)

## Uses

### 🧠 Train-of-thought recovery

Autosave isn’t always an option, in those cases you can easily recover your train of thought, a screenshot to use as a stencil, or extracted copy from memories recorded.

### 🌏 Search across applications

A lot of research involves collating information from multiple sources; internal tools like confluence, websites like wikipedia, pdf and doc files etc; When searching for something we don’t always remember the source (or it's at the tip of your tongue)

## Features

> - When no OpenAI key is supplied, Cyte is completely private, data is stored on disk only, no outside connections are made
> - Pause/Restart recording easily
> - Set applications that are not to be recorded (while taking keystrokes)
> - Chat your data; ask questions about work you've done

## Development

Happy to accept PRs related to any of the following

### Issues

- App sandbox is disabled to allow file tracking; [instead should request document permissions](https://stackoverflow.com/a/70972475)
- Timeline slider not updating while video playing (timeJumped notification not sent until pause)
- Build process fails on Github (Needs signing cert installed to sign embedded content?)
- Sometimes app icons do not show on timeline view
- Only the top result is highlighted in timeline view
- Should not [perform video analysis](https://developer.apple.com/documentation/avkit/avplayerview/3986556-allowsvideoframeanalysis) on feed

### Refactor

- Extract usage and search bars to own views from ContentView
- Extract episode slider from EpisodeTimelineView into own view
- Duplicate code in vision analysis handlers and get active interval (timeline views)

### Feature requests
- Keyboard navigation events: Return to open selected episode, escape to pop timeline view
- Fallback to object recognition
- Encryption e.g. Filevault?