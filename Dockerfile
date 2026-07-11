FROM ghcr.io/cirruslabs/flutter:stable

RUN git config --system --add safe.directory /sdks/flutter
RUN yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platforms;android-35" "cmake;3.22.1" "ndk;28.2.13676358" \
    && flutter precache --android \
    && chmod -R a+rwX /sdks/flutter /opt/android-sdk-linux

WORKDIR /workspace

ENV PUB_CACHE=/workspace/.dart_tool/pub-cache
ENV GRADLE_USER_HOME=/workspace/.gradle

CMD ["flutter", "--version"]
