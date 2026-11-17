package com.universidad.enviosservice.estrategia;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.junit.jupiter.api.Assertions.assertEquals;

class EnvioInternacionalStrategyTest {

    private final EnvioInternacionalStrategy estrategia = new EnvioInternacionalStrategy();

    @ParameterizedTest(name = "{0} kg, {1} km -> {2}")
    @CsvSource({
            "3.0,  100.0, 230.0",    // 180 + 50
            "8.0,  100.0, 239.0",    // 230 + 3 x 3.0
            "25.0, 100.0, 297.5"     // 230 + 45 + 5 x 4.5
    })
    void calcular_porTramoDePeso_aplicaLaTarifaDelTramo(double pesoKg, double distanciaKm, double esperado) {
        assertEquals(esperado, estrategia.calcular(pesoKg, distanciaKm), 0.001);
    }

    @ParameterizedTest(name = "{0} km -> {1}")
    @CsvSource({
            "5000.0, 9050.0",        // límite: sin recargo
            "5001.0, 9151.8"         // más de 5000 km: +100
    })
    void calcular_porDistancia_agregaRecargoDesde5001Km(double distanciaKm, double esperado) {
        assertEquals(esperado, estrategia.calcular(3.0, distanciaKm), 0.001);
    }
}
