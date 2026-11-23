# The cart service as a container image, built in two stages: Maven
# builds the jar, and a smaller Java runtime image runs it.
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q dependency:go-offline
COPY src src
RUN mvn -q package

FROM docker.io/library/eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/cart.jar cart.jar
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "cart.jar"]
