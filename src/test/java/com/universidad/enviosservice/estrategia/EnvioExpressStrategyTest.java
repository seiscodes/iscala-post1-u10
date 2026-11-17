package com.universidad.enviosservice.estrategia;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.junit.jupiter.api.Assertions.assertEquals;

class EnvioExpressStrategyTest {

    private final EnvioExpressStrategy estrategia = new EnvioExpressStrategy();

    @ParameterizedTest(name = "{0} kg, {1} km -> {2}")
    @CsvSource({
            "3.0,  100.0, 156.0",    // (100 x 1.2) x 1.3
            "8.0,  100.0, 161.85",   // (120 + 3 x 1.5) x 1.3
            "25.0, 100.0, 198.25"    // (120 + 22.5 + 5 x 2.0) x 1.3
    })
    void calcular_porTramoDePeso_aplicaTarifaYFactorExpress(double pesoKg, double distanciaKm, double esperado) {
        assertEquals(esperado, estrategia.calcular(pesoKg, distanciaKm), 0.001);
    }

    @ParameterizedTest(name = "{0} km -> {1}")
    @CsvSource({
            "500.0, 780.0",          // sin recargo
            "501.0, 814.06"          // (601.2 + 25) x 1.3: el recargo también se multiplica por 1.3
    })
    void calcular_porDistancia_elRecargoEntraAntesDelFactor(double distanciaKm, double esperado) {
        assertEquals(esperado, estrategia.calcular(3.0, distanciaKm), 0.001);
    }
}
