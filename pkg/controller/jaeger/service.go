package jaeger

import (
	"context"

	log "github.com/sirupsen/logrus"
	"go.opentelemetry.io/otel"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	v1 "github.com/jaegertracing/jaeger-operator/apis/v1"
	"github.com/jaegertracing/jaeger-operator/pkg/inventory"
	"github.com/jaegertracing/jaeger-operator/pkg/tracing"
)

func (r *ReconcileJaeger) applyServices(ctx context.Context, jaeger v1.Jaeger, desired []corev1.Service) error {
	tracer := otel.GetTracerProvider().Tracer(v1.ReconciliationTracer)
	ctx, span := tracer.Start(ctx, "applyServices")
	defer span.End()

	opts := []client.ListOption{
		client.InNamespace(jaeger.Namespace),
		client.MatchingLabels(map[string]string{
			"app.kubernetes.io/instance":   jaeger.Name,
			"app.kubernetes.io/managed-by": "jaeger-operator",
		}),
	}
	list := &corev1.ServiceList{}
	if err := r.rClient.List(ctx, list, opts...); err != nil {
		return tracing.HandleError(err, span)
	}

	inv := inventory.ForServices(list.Items, desired)
	for i := range inv.Create {
		d := inv.Create[i]
		jaeger.Logger().WithFields(log.Fields{
			"service":   d.Name,
			"namespace": d.Namespace,
		}).Debug("creating service")
		if err := r.client.Create(ctx, &d); err != nil {
			return tracing.HandleError(err, span)
		}
	}

	for i := range inv.Update {
		d := inv.Update[i]
		jaeger.Logger().WithFields(log.Fields{
			"service":   d.Name,
			"namespace": d.Namespace,
		}).Debug("updating service")
		if err := r.client.Update(ctx, &d); err != nil {
			return tracing.HandleError(err, span)
		}
	}

	for i := range inv.Delete {
		d := inv.Delete[i]
		jaeger.Logger().WithFields(log.Fields{
			"service":   d.Name,
			"namespace": d.Namespace,
		}).Debug("deleting service")
		if err := r.client.Delete(ctx, &d); err != nil {
			return tracing.HandleError(err, span)
		}
	}

	return nil
}
