package model

import (
	"github.com/zitadel/zitadel/v2/internal/crypto"
	es_models "github.com/zitadel/zitadel/v2/internal/eventstore/v1/models"
)

type OrgDomain struct {
	es_models.ObjectRoot
	Domain         string
	Primary        bool
	Verified       bool
	ValidationType OrgDomainValidationType
	ValidationCode *crypto.CryptoValue
}

type OrgDomainValidationType int32

const (
	OrgDomainValidationTypeUnspecified OrgDomainValidationType = iota
	OrgDomainValidationTypeHTTP
	OrgDomainValidationTypeDNS
)
