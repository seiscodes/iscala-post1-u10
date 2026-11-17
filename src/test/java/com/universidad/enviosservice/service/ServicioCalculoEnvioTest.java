package com.universidad.enviosservice.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ServicioCalculoEnvioTest {

    private final ServicioCalculoEnvio servicio = new ServicioCalculoEnvio();

    // ---- Pruebas de partida (Parte 1) ----

    @Test
    void calculaEnvioEstandarPesoBajo() {
        double costo = servicio.calcularCosto("ESTANDAR", 3.0, 100.0, "REGULAR", false);
        assertEquals(50.0, costo, 0.01);
    }

    @Test
    void aplicaDescuentoClientePremium() {
        double costo = servicio.calcularCosto("ESTANDAR", 3.0, 100.0, "PREMIUM", false);
        assertEquals(45.0, costo, 0.01);
    }

    // ---- Ramas del orquestador que la suite inicial no cubría (Parte 2) ----

    @Test
    void calcularCosto_paqueteFragil_agrega15PorCiento() {
        assertEquals(57.5, servicio.calcularCosto("ESTANDAR", 3.0, 100.0, "REGULAR", true), 0.001);
    }

    @Test
    void calcularCosto_clienteCorporativo_descuenta15PorCiento() {
        assertEquals(42.5, servicio.calcularCosto("ESTANDAR", 3.0, 100.0, "CORPORATIVO", false), 0.001);
    }

    @Test
    void calcularCosto_fragilYPremium_primeroRecargaYLuegoDescuenta() {
        // 50 x 1.15 = 57.5 y luego x 0.9
        assertEquals(51.75, servicio.calcularCosto("ESTANDAR", 3.0, 100.0, "PREMIUM", true), 0.001);
    }

    @Test
    void calcularCosto_metodoNoSoportado_lanzaExcepcionConElNombre() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> servicio.calcularCosto("AEREO", 3.0, 100.0, "REGULAR", false));
        assertEquals("Metodo de envio no soportado: AEREO", ex.getMessage());
    }

    @Test
    void calcularCosto_overnightMasDe300Km_propagaLaRestriccionDeLaEstrategia() {
        assertThrows(IllegalArgumentException.class,
                () -> servicio.calcularCosto("OVERNIGHT", 3.0, 450.0, "REGULAR", false));
    }

    /**
     * Mismos resultados que la versión original (tag parte1-inicial) para un caso de cada
     * método combinado con fragilidad y tipo de cliente.
     */
    @ParameterizedTest(name = "{0} {1}kg {2}km {3} fragil={4} -> {5}")
    @CsvSource({
            "ESTANDAR,      8.0,  600.0, CORPORATIVO, true,  305.371",
            "EXPRESS,       25.0, 100.0, PREMIUM,     false, 178.425",
            "OVERNIGHT,     8.0,  250.0, REGULAR,     true,  606.625",
            "INTERNACIONAL, 25.0, 6000.0, CORPORATIVO, false, 9364.875"
    })
    void calcularCosto_combinaciones_coincideConLaVersionOriginal(String metodo, double peso, double distancia,
                                                                 String cliente, boolean fragil, double esperado) {
        assertEquals(esperado, servicio.calcularCosto(metodo, peso, distancia, cliente, fragil), 0.001);
    }
}
