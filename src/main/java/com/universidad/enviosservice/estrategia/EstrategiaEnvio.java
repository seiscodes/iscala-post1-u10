package com.universidad.enviosservice.estrategia;

/** Strategy: cada método de envío calcula su costo base a partir del peso y la distancia. */
public interface EstrategiaEnvio {

    double calcular(double pesoKg, double distanciaKm);
}
