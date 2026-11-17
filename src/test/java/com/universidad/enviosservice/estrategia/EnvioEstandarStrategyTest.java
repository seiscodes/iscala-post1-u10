package com.universidad.enviosservice.estrategia;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.junit.jupiter.api.Assertions.assertEquals;

class EnvioEstandarStrategyTest {

    private final EnvioEstandarStrategy estrategia = new EnvioEstandarStrategy();

    @ParameterizedTest(name = "{0} kg, {1} km -> {2}")
    @CsvSource({
            "3.0,  100.0, 50.0",   // tramo hasta 5 kg
            "5.0,  100.0, 50.0",   // límite: 5 kg todavía es el primer tramo
            "8.0,  100.0, 52.4",   // tramo 5-20 kg
            "20.0, 100.0, 62.0",   // límite: 20 kg todavía es el segundo tramo
            "25.0, 100.0, 68.0"    // tramo de más de 20 kg
    })
    void calcular_porTramoDePeso_aplicaLaTarifaDelTramo(double pesoKg, double distanciaKm, double esperado) {
        assertEquals(esperado, estrategia.calcular(pesoKg, distanciaKm), 0.001);
    }

    @ParameterizedTest(name = "{0} km -> {1}")
    @CsvSource({
            "500.0, 250.0",        // límite: 500 km no lleva recargo
            "501.0, 260.5"         // más de 500 km: +10
    })
    void calcular_porDistancia_agregaRecargoDesde501Km(double distanciaKm, double esperado) {
        assertEquals(esperado, estrategia.calcular(3.0, distanciaKm), 0.001);
    }
}
